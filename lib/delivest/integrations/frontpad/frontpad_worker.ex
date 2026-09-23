defmodule Delivest.Integrations.Frontpad.FrontpadWorker do
  use Oban.Worker,
    queue: :frontpad,
    max_attempts: 7,
    unique: [period: 300, fields: [:args]]

  require Logger

  alias Delivest.Oms.Orders
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Frontpad.FrontpadView
  alias Delivest.HTTP.Client, as: HttpClient
  alias Delivest.Net

  @fibonacci_intervals [1, 1, 2, 3, 5, 8, 13]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Обнуляем индекс массива с учетом текущей попытки (в секундах для Oban)
    multiplier = Enum.at(@fibonacci_intervals, attempt - 1, List.last(@fibonacci_intervals))
    multiplier * 10
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"order_id" => order_id, "branch_id" => branch_id},
          attempt: attempt
        } = job
      ) do
    with {:ok, order} <- fetch_order(order_id),
         {:ok, branch} <- fetch_branch(branch_id),
         {:ok, view} <- build_frontpad_view(order, branch),
         form_params <- FrontpadView.to_form_params(view),
         _ =
           Logger.info(
             "Frontpad sending order #{order.id} (attempt #{attempt}/#{job.max_attempts}). Params: #{inspect(form_params)}"
           ),
         {:ok, response} <- execute_request(form_params) do
      handle_frontpad_response(order, response)
      :ok
    else
      {:error, reason} = error ->
        error_message = inspect(reason)

        Logger.error(
          "Frontpad send failed (attempt #{attempt}/#{job.max_attempts}) for order #{order_id}. Reason: #{error_message}"
        )

        update_order_failure_status(order_id, attempt, job.max_attempts, error_message)

        error
    end
  end

  defp fetch_order(order_id) do
    case Orders.get_order!(order_id) do
      nil -> {:error, :order_not_found}
      order -> {:ok, order}
    end
  end

  defp fetch_branch(branch_id) do
    case Delivest.Repo.get(Branch, branch_id) do
      nil -> {:error, :branch_not_found}
      branch -> {:ok, Delivest.Repo.preload(branch, :info)}
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

  defp update_order_failure_status(order_id, attempt, max_attempts, error_message) do
    with %{} = order <- Orders.get_order!(order_id) do
      status = if attempt >= max_attempts, do: "failed", else: "pending"

      last_error =
        if attempt >= max_attempts,
          do: "Max attempts reached. Last error: #{error_message}",
          else: error_message

      attrs = %{
        "crm_info" => %{
          "status" => status,
          "attempts" => attempt,
          "last_error" => last_error
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
