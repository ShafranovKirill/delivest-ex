defmodule Delivest.SiteSnapshot.Assets do
  @moduledoc """
  Media references that live outside `Media.File`: brand images, modifier
  photos, tag icons and the generated brand icon set.
  """

  alias Delivest.SiteSnapshot.Fields

  def branch_keys(data) do
    franchise = data["franchise"] || %{}
    modifiers = Enum.map(data["modifiers"] || [], & &1["photo_key"])
    tags = Enum.map(data["tags"] || [], & &1["icon_key"])
    expand(franchise, modifiers, tags)
  end

  def franchise_keys(data) do
    modifiers =
      Enum.flat_map(data["branches"], fn branch ->
        Enum.map(branch["modifiers"] || [], & &1["photo_key"])
      end)

    tags =
      Enum.flat_map(data["branches"], fn branch ->
        Enum.map(branch["tags"] || [], & &1["icon_key"])
      end)

    expand(data["franchise"] || %{}, modifiers, tags)
  end

  def expand(franchise, modifiers, tags) do
    images =
      Map.take(franchise, Enum.map(Fields.image_fields(), &Atom.to_string/1)) |> Map.values()

    Enum.reject(images ++ modifiers ++ tags, &is_nil/1)
    |> Enum.flat_map(fn key ->
      if String.starts_with?(key, "franchise/icon/"),
        do:
          Enum.map(
            ~w(favicon.ico icon-32.png apple-touch-icon.png icon-192.png icon-512.png),
            &"#{key}/#{&1}"
          ),
        else: [key]
    end)
  end

  def private_media?(branch),
    do: Enum.any?(branch["media"] || [], &(&1["is_private"] != false))

  def image_type(<<137, "PNG", 13, 10, 26, 10, _::binary>>), do: "image/png"
  def image_type(<<255, 216, 255, _::binary>>), do: "image/jpeg"
  def image_type(<<"RIFF", _::32, "WEBP", _::binary>>), do: "image/webp"
  def image_type(<<0, 0, 1, 0, _::binary>>), do: "image/x-icon"
  def image_type(_), do: nil

  def storage_key(reference, body) do
    case Regex.run(
           ~r{/franchise/icon/[^/]+/(favicon\.ico|icon-32\.png|apple-touch-icon\.png|icon-192\.png|icon-512\.png)$},
           reference
         ) do
      [_, filename] -> "franchise/icon/snapshot-#{sha(Path.dirname(reference))}/#{filename}"
      _ -> "site-snapshot/#{sha([reference, <<0>>, body])}"
    end
  end

  def icon_directory(reference, key) do
    if String.contains?(reference, "/franchise/icon/") do
      {Path.dirname(reference), Path.dirname(key)}
    end
  end

  def sha(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
