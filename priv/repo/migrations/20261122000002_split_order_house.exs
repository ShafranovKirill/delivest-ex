defmodule Delivest.Repo.Migrations.SplitOrderHouse do
  use Ecto.Migration

  alias Delivest.Geo.House

  def up do
    %{rows: rows} =
      repo().query!(
        "SELECT id, address->>'house' FROM orders WHERE address->>'house' ~* '(к|корп|стр)'"
      )

    for [id, house] <- rows do
      parts = House.split(house)

      repo().query!(
        "UPDATE orders SET address = address || jsonb_build_object('house', $2::text, 'block', $3::text, 'building', $4::text) WHERE id = $1",
        [id, parts.house, parts.block, parts.building]
      )
    end
  end

  def down, do: :ok
end
