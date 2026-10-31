defmodule Delivest.Identity.PhoneTest do
  use ExUnit.Case, async: true

  alias Delivest.Identity.Phone

  test "splits the extension from a substitute number" do
    assert Phone.split("+79990001122") == {"+79990001122", nil}
    assert Phone.split("+7 999 000-11-22, 1234") == {"+79990001122", "1234"}
    assert Phone.split("89990001122 доб. 55") == {"+79990001122", "55"}
    assert Phone.split("+79990001122 ext 7") == {"+79990001122", "7"}
    assert Phone.split("+375291234567") == {"+375291234567", nil}
    assert Phone.split(nil) == {nil, nil}
  end
end
