defmodule Delivest.Integrations.YandexEda.OrderAttrs do
  alias Delivest.Integrations.YandexEda.{
    AcceptDeadline,
    BranchSettings,
    Clock,
    OrderAddress,
    OrderComment,
    OrderPricing,
    OrderRequest
  }

  def build(%OrderRequest{} = request, cart, branch, settings) do
    %{
      "status" => status(settings),
      "cart_id" => cart.id,
      "branch_id" => branch.id,
      "fulfillment_type" => fulfillment(request.discriminator),
      "payment_method" => "cash",
      "comment" => OrderComment.text(request),
      "cook_by" => cook_by(request, branch.info),
      "address" => OrderAddress.build(request.address)
    }
  end

  def opts(%OrderRequest{} = request, branch, %BranchSettings{} = settings) do
    [
      source: "yandex_eda",
      channel: channel(request, branch, settings),
      pricing: OrderPricing.fixed(request),
      paid_online: request.paid
    ]
  end

  defp fulfillment("marketplace"), do: "delivery"
  defp fulfillment(_discriminator), do: "pickup"

  defp status(%BranchSettings{accept_mode: :manual}), do: "created"
  defp status(_settings), do: "accepted"

  defp cook_by(%OrderRequest{discriminator: "marketplace", target_at: at}, %{
         delivery_time: minutes
       })
       when is_integer(minutes),
       do: at |> DateTime.add(-minutes, :minute) |> Clock.local()

  defp cook_by(%OrderRequest{target_at: at}, _info), do: Clock.local(at)

  defp channel(request, branch, settings) do
    %{
      provider: "yandex_eda",
      external_id: request.eats_id,
      external_number: request.eats_id,
      platform: request.platform,
      delivery: request.discriminator,
      details:
        %{
          "client_name" => request.client_name,
          "phone" => request.phone,
          "delivery_fee" => request.delivery_fee,
          "accept_by" => accept_by(settings, branch.info),
          "request" => request.raw
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
    }
  end

  defp accept_by(%BranchSettings{accept_mode: :manual, accept_minutes: minutes}, info),
    do: (info && info.working_hours) |> AcceptDeadline.at(minutes) |> DateTime.to_iso8601()

  defp accept_by(_settings, _info), do: nil
end
