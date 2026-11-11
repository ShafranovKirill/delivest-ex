defmodule Delivest.Analytics.OrderIdentity do
  @moduledoc "Immutable identity evidence captured only at initial order creation."

  alias Delivest.Repo

  def capture(order, opts, as_of_at) do
    authenticated = opts[:authenticated_client_id]

    {kind, client_id} =
      cond do
        is_binary(authenticated) and authenticated == order.client_id -> {"client", authenticated}
        is_binary(opts[:analytics_guest_id]) -> {"guest", nil}
        true -> {"unknown", nil}
      end

    Repo.query!(
      """
      INSERT INTO analytics_order_identities
        (order_id, verified_client_id, owner_kind, as_of_at, inserted_at)
      VALUES ($1::text::uuid, $2::text::uuid, $3, $4, $4)
      ON CONFLICT (order_id) DO NOTHING
      """,
      [order.id, client_id, kind, as_of_at]
    )

    :ok
  end
end
