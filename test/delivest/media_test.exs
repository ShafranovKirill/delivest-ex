defmodule Delivest.MediaTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Media
  alias Delivest.Media.File

  defp file_attrs(owner_id, attrs \\ %{}) do
    Map.merge(
      %{
        bucket: "test",
        key: "products/file.jpg",
        original_name: "file.jpg",
        mime_type: "image/jpeg",
        size: 42,
        context: :product,
        owner_id: owner_id
      },
      attrs
    )
  end

  describe "create_file/1" do
    test "creates and persists a media file" do
      owner = insert(:staff)

      assert {:ok, %File{} = file} = Media.create_file(file_attrs(owner.id))
      assert file.bucket == "test"
      assert file.key == "products/file.jpg"
      assert file.context == :product
      assert Media.get_file(file.id).id == file.id
    end

    test "returns validation errors for invalid file attributes" do
      owner = insert(:staff)

      assert {:error, changeset} = Media.create_file(file_attrs(owner.id, %{size: 0}))
      assert "must be greater than 0" in errors_on(changeset).size
    end

    test "returns an error for a duplicate bucket and key" do
      owner = insert(:staff)
      attrs = file_attrs(owner.id)
      assert {:ok, _file} = Media.create_file(attrs)

      assert {:error, changeset} = Media.create_file(attrs)
      assert "has already been taken" in errors_on(changeset).bucket
    end
  end

  describe "get_file/1" do
    test "returns nil for a nil id" do
      assert Media.get_file(nil) == nil
    end

    test "returns nil when the file does not exist" do
      assert Media.get_file(Ecto.UUID.generate()) == nil
    end
  end

  describe "delete_file_by_key/1" do
    test "returns an empty result for an unknown key" do
      assert {:ok, nil} = Media.delete_file_by_key("products/missing.jpg")
    end
  end
end
