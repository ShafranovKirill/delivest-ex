defmodule Delivest.Analytics.OrderReceipts do
  @moduledoc "Optional analytics writes inside the core order transaction."

  alias Delivest.Features
  alias Delivest.Analytics.OrderIdentity
  alias Delivest.Advertising.OrderCapture
  alias Delivest.Funnel.OrderCapture, as: FunnelOrderCapture

  def cutoff, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  def capture(order, opts, as_of_at) do
    branch = {:branch, order.branch_id}

    requests =
      for feature <- ["analytics_links", "analytics_funnel", "analytics_extended"],
          {:ok, generation} <- [Features.snapshot(feature, branch)],
          do: {feature, branch, generation}

    case publish(requests, order, opts, as_of_at) do
      {:error, :disabled} ->
        valid =
          Enum.filter(requests, fn {feature, scope, token} ->
            Features.still_enabled?(feature, scope, token)
          end)

        if valid == requests do
          {:ok, nil}
        else
          case publish(valid, order, opts, as_of_at) do
            {:error, :disabled} -> {:ok, nil}
            result -> result
          end
        end

      result ->
        result
    end
  end

  defp publish([], _order, _opts, _as_of_at), do: {:ok, nil}

  defp publish(requests, order, opts, as_of_at) do
    case Features.publish_if_enabled(requests, fn ->
           if requested?(requests, "analytics_links"),
             do:
               OrderCapture.capture(
                 order,
                 opts[:authenticated_client_id],
                 opts[:analytics_guest_id],
                 as_of_at
               )

           if requested?(requests, "analytics_funnel"),
             do: FunnelOrderCapture.capture(order, owner(opts), as_of_at)

           if requested?(requests, "analytics_extended"),
             do: OrderIdentity.capture(order, opts, as_of_at)

           :ok
         end) do
      {:ok, :ok} -> {:ok, nil}
      {:error, :disabled} -> {:error, :disabled}
    end
  end

  defp requested?(requests, feature),
    do: Enum.any?(requests, fn {name, _, _} -> name == feature end)

  defp owner(opts) do
    cond do
      opts[:authenticated_client_id] -> "client:" <> opts[:authenticated_client_id]
      opts[:analytics_guest_id] -> "guest:" <> opts[:analytics_guest_id]
      true -> nil
    end
  end
end
