defmodule Delivest.Media.Thumbnail do
  alias Vix.Vips.{Image, Operation}

  @sizes %{product: 800, stock: 1600}
  @product_variants [192, 384, 800]

  def key(original_key), do: Path.rootname(original_key) <> "_thumb.webp"

  def variant_key(original_key, width, original) do
    digest = :crypto.hash(:sha256, original) |> Base.encode16(case: :lower)
    Path.rootname(original_key) <> "_thumb_v2_#{width}_#{digest}.webp"
  end

  def product_variants, do: @product_variants

  def build(binary, context), do: build_width(binary, Map.fetch!(@sizes, context))

  def build_width(binary, width) do
    with {:ok, image} <-
           Operation.thumbnail_buffer(binary, width, height: width, size: :VIPS_SIZE_DOWN),
         {:ok, webp} <- Image.write_to_buffer(image, ".webp[Q=80,strip]") do
      {:ok, webp, Image.width(image)}
    else
      {:error, _reason} -> {:error, :invalid_image}
    end
  end
end
