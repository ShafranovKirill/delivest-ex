defmodule Delivest.Advertising.OrderCapture do
  @moduledoc "Captures a credible advertising touch in the fresh order transaction."

  alias Delivest.Advertising.{Attribution, OrderAttribution}
  alias Delivest.Repo

  def capture(order, client_id, guest_id, as_of_at) do
    if client_id || guest_id do
      if client_id && guest_id, do: {:ok, _} = Attribution.claim(client_id, guest_id, as_of_at)

      case Attribution.last_touch(client_id, guest_id, as_of_at) do
        nil ->
          :ok

        click ->
          Repo.insert_all(
            OrderAttribution,
            [
              %{
                order_id: order.id,
                link_id: click.link_id,
                landing_branch_id: click.branch_id,
                clicked_at: click.clicked_at,
                as_of_at: as_of_at,
                inserted_at: as_of_at
              }
            ],
            on_conflict: :nothing
          )

          :ok
      end
    else
      :ok
    end
  end
end
