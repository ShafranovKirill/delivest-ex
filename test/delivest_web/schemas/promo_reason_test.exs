defmodule DelivestWeb.Schemas.PromoReasonTest do
  use ExUnit.Case, async: true

  alias DelivestWeb.Client.Cart.PromoJSON
  alias DelivestWeb.Schemas.CartSchemas.PromoReason

  test "first-order reason is included in the API contract and JSON" do
    assert "first_order" in PromoReason.schema().properties.type.enum
    assert %{type: :first_order} = PromoJSON.reason(%{type: :first_order})
  end
end
