defmodule Delivest.Media.Thumbnail do
  alias Vix.Vips.{Image, Operation}

  @sizes %{product: 800, stock: 1600}

  def key(original_key), do: Path.rootname(original_key) <> "_thumb.webp"

  def build(binary, context) do
    size = Map.fetch!(@sizes, context)

    with {:ok, image} <-
           Operation.thumbnail_buffer(binary, size, height: size, size: :VIPS_SIZE_DOWN),
         {:ok, webp} <- Image.write_to_buffer(image, ".webp[Q=80,strip]") do
      {:ok, webp}
    else
      {:error, _reason} -> {:error, :invalid_image}
    end
  end
end
