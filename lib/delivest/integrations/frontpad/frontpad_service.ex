defmodule Delivest.Integrations.Frontpad.FrontpadService do
  require Logger

  alias Delivest.Oms.Orders
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Frontpad.FrontpadView
  alias Delivest.HTTP.Client, as: HttpClient
  alias Delivest.Net

  @fibonacci_intervals [1, 1, 2, 3, 5, 8, 13]
  @max_attempts length(@fibonacci_intervals)

  @spec enabled?(Branch.t() | nil) :: boolean()
  def enabled?(%Branch{info: %{frontpad_enabled: true}}), do: true
  def enabled?(_), do: false

  @spec api_key(Branch.t() | nil) :: String.t() | nil
  def api_key(%Branch{info: %{frontpad_api_key: api_key}}) when not is_nil(api_key), do: api_key
  def api_key(_), do: nil

  @spec settings(Branch.t() | nil) :: map() | nil
  def settings(%Branch{info: %{frontpad_settings: settings}}) do
    case settings do
      %{frontpad_branch_id: fb_id} when not is_nil(fb_id) -> %{frontpad_branch_id: fb_id}
      _ -> nil
    end
  end

  def settings(_), do: nil

  def create_order(attrs, %Branch{} = branch) do
    enriched_attrs = Map.put(attrs, "status", "crm")

    case Orders.create_order(enriched_attrs) do
      {:ok, order} = result ->
        send_order_to_frontpad_async(order, branch)
        result

      {:error, _step, _reason} = error ->
        error
    end
  end

  defp send_order_to_frontpad_async(order, branch) do
    Task.start(fn ->
      perform_request_with_retry(order, branch, 1)
    end)
  end

  @spec perform_request_with_retry(Delivest.Oms.Order.t(), Branch.t(), integer()) :: term()
  defp perform_request_with_retry(order, branch, attempt) do
    with {:ok, view} <- build_frontpad_view(order, branch),
         form_params <- FrontpadView.to_form_params(view),
         _ =
           Logger.info(
             "Frontpad sending order #{order.id} (attempt #{attempt}/#{@max_attempts}). Params: #{inspect(form_params)}"
           ),
         {:ok, response} <- execute_request(form_params) do
      handle_frontpad_response(order, response)
    else
      {:error, reason} ->
        handle_frontpad_error_or_retry(order, branch, attempt, reason)
    end
  end

  @spec execute_request(list()) :: {:ok, map()} | {:error, term()}
  defp execute_request(form_params) do
    opts = [
      base_url: "https://app.frontpad.ru",
      format: :form,
      decode_json: true
    ]

    case HttpClient.post("/api/index.php?new_order", form_params, opts) do
      {:ok, %{"result" => "success"} = body} when is_map(body) ->
        {:ok, body}

      {:ok, %{"result" => "error", "error" => err}} ->
        {:error, {:frontpad_api_error, err}}

      {:ok, body} when is_map(body) ->
        {:error, {:unexpected_response, body}}

      {:ok, binary} when is_binary(binary) ->
        case Jason.decode(binary) do
          {:ok, %{"result" => "success"} = decoded} -> {:ok, decoded}
          {:ok, %{"result" => "error", "error" => err}} -> {:error, {:frontpad_api_error, err}}
          {:ok, other} -> {:error, {:unexpected_response, other}}
          {:error, reason} -> {:error, {:invalid_json, binary, reason}}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_frontpad_view(Delivest.Oms.Order.t(), Branch.t()) ::
          {:ok, FrontpadView.t()} | {:error, atom()}
  defp build_frontpad_view(order, branch) do
    product_ids = Enum.map(order.items, & &1.product_id)
    products_map = Net.list_products_by_ids(product_ids)

    FrontpadView.build(order, branch, products_map)
  end

  @spec handle_frontpad_response(Delivest.Oms.Order.t(), map()) :: term()
  defp handle_frontpad_response(order, response) do
    crm_id = to_string(response["order_id"])

    Logger.info(
      "Frontpad order successfully created! Order ID in CRM: #{crm_id}, Response: #{inspect(response)}"
    )

    attrs = %{
      "crm_id" => crm_id,
      "crm_info" => %{
        "status" => "sent",
        "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    update_crm_info(order, attrs)
  end

  @spec handle_frontpad_error_or_retry(Delivest.Oms.Order.t(), Branch.t(), integer(), term()) ::
          term()
  defp handle_frontpad_error_or_retry(order, branch, attempt, reason) do
    error_message = inspect(reason)

    Logger.error(
      "Frontpad send failed (attempt #{attempt}/#{@max_attempts}) for order #{order.id}. Reason: #{error_message}"
    )

    if attempt < @max_attempts do
      multiplier = Enum.at(@fibonacci_intervals, attempt - 1)
      sleep_ms = multiplier * 10 * 1000

      attrs = %{
        "crm_info" => %{
          "status" => "pending",
          "attempts" => attempt,
          "last_error" => error_message
        }
      }

      update_crm_info(order, attrs)

      Process.sleep(sleep_ms)
      perform_request_with_retry(order, branch, attempt + 1)
    else
      attrs = %{
        "crm_info" => %{
          "status" => "failed",
          "attempts" => attempt,
          "last_error" => "Max attempts reached. Last error: #{error_message}"
        }
      }

      update_crm_info(order, attrs)
    end
  end

  @spec update_crm_info(Delivest.Oms.Order.t(), map()) :: term()
  defp update_crm_info(order, attrs) do
    order
    |> Delivest.Oms.Order.changeset(attrs)
    |> Delivest.Repo.update()
  end
end
