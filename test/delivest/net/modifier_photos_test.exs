defmodule Delivest.Net.ModifierPhotosTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Net.{Modifier, ModifierGroup, Modifiers}
  alias Delivest.Repo

  setup do
    Delivest.S3Stub.record(self())
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    group = Repo.insert!(%ModifierGroup{name: "Добавки", min: 0, max: 3})
    modifier = Repo.insert!(%Modifier{group_id: group.id, name: "Джем", price: 5_000})
    %{admin: admin, modifier: modifier}
  end

  test "a photo is stored, replaces the previous one and can be removed", %{
    admin: admin,
    modifier: modifier
  } do
    assert {:ok, %{photo_key: "modifiers/" <> _ = key} = modifier} =
             Modifiers.put_photo(admin, modifier, Delivest.S3Stub.png(900, 700))

    assert_received {:s3, "PUT", "/delivest/" <> ^key, _body}
    assert Modifiers.photo_url(modifier) =~ key

    assert {:ok, %{photo_key: new_key}} =
             Modifiers.put_photo(admin, modifier, Delivest.S3Stub.png(500, 500))

    assert new_key != key
    assert_received {:s3, "DELETE", "/delivest/" <> ^key, _body}

    assert {:ok, %{photo_key: nil} = cleared} =
             Modifiers.remove_photo(admin, Modifiers.get_modifier(modifier.id))

    assert Modifiers.photo_url(cleared) == nil
  end

  test "garbage is not a photo", %{admin: admin, modifier: modifier} do
    assert {:error, :invalid_image} = Modifiers.put_photo(admin, modifier, "not an image")
    refute_received {:s3, "PUT", _, _}
  end
end
