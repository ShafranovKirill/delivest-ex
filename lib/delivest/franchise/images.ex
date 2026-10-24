defmodule Delivest.Franchise.Images do
  alias Vix.Vips.{Image, Operation}

  @white [255.0, 255.0, 255.0]
  @icon_min 192
  @share_width 1200
  @share_height 630
  @share_min_width 600
  @logo_height 160
  @logo_max_width 640
  @logo_min_height 48

  def icon_min, do: @icon_min
  def share_size, do: {@share_width, @share_height}
  def share_min_width, do: @share_min_width
  def logo_min_height, do: @logo_min_height

  def icon(binary) do
    with {:ok, image} <- load(binary),
         :ok <- at_least(image, @icon_min, @icon_min),
         {:ok, png_16} <- square_png(binary, 16),
         {:ok, png_32} <- square_png(binary, 32),
         {:ok, png_48} <- square_png(binary, 48),
         {:ok, png_192} <- square_png(binary, 192),
         {:ok, png_512} <- square_png(binary, 512),
         {:ok, apple} <- square_png(binary, 180, flatten: true) do
      {:ok,
       [
         {"favicon.ico", ico([{16, png_16}, {32, png_32}, {48, png_48}]), "image/x-icon"},
         {"icon-32.png", png_32, "image/png"},
         {"apple-touch-icon.png", apple, "image/png"},
         {"icon-192.png", png_192, "image/png"},
         {"icon-512.png", png_512, "image/png"}
       ]}
    end
  end

  def share_image(binary) do
    with {:ok, image} <- load(binary),
         :ok <- at_least(image, @share_min_width, 1),
         {:ok, thumb} <-
           Operation.thumbnail_buffer(binary, @share_width,
             height: @share_height,
             crop: :VIPS_INTERESTING_CENTRE,
             size: :VIPS_SIZE_BOTH
           ),
         {:ok, flat} <- flatten(thumb),
         {:ok, jpeg} <- Image.write_to_buffer(flat, ".jpg[Q=85,strip]") do
      {:ok, jpeg}
    else
      {:error, :too_small} -> {:error, :too_small}
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  def logo(binary) do
    with {:ok, image} <- load(binary),
         :ok <- at_least(image, 1, @logo_min_height) do
      fitted_png(binary, @logo_max_width, @logo_height)
    end
  end

  defp load(binary) do
    case Image.new_from_buffer(binary) do
      {:ok, image} -> {:ok, image}
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  defp at_least(image, width, height) do
    if Image.width(image) >= width and Image.height(image) >= height,
      do: :ok,
      else: {:error, :too_small}
  end

  defp square_png(binary, size, opts \\ []) do
    with {:ok, thumb} <-
           Operation.thumbnail_buffer(binary, size,
             height: size,
             crop: :VIPS_INTERESTING_CENTRE,
             size: :VIPS_SIZE_BOTH
           ),
         {:ok, image} <- if(opts[:flatten], do: flatten(thumb), else: {:ok, thumb}),
         {:ok, png} <- Image.write_to_buffer(image, ".png[strip]") do
      {:ok, png}
    else
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  defp fitted_png(binary, width, height) do
    with {:ok, thumb} <-
           Operation.thumbnail_buffer(binary, width, height: height, size: :VIPS_SIZE_DOWN),
         {:ok, png} <- Image.write_to_buffer(thumb, ".png[strip]") do
      {:ok, png}
    else
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  defp flatten(image) do
    if Image.has_alpha?(image),
      do: Operation.flatten(image, background: @white),
      else: {:ok, image}
  end

  defp ico(entries) do
    count = length(entries)
    header = <<0::little-16, 1::little-16, count::little-16>>

    {directory, _offset} =
      Enum.map_reduce(entries, 6 + 16 * count, fn {size, png}, offset ->
        entry =
          <<size::8, size::8, 0::8, 0::8, 1::little-16, 32::little-16, byte_size(png)::little-32,
            offset::little-32>>

        {entry, offset + byte_size(png)}
      end)

    IO.iodata_to_binary([header, directory, Enum.map(entries, &elem(&1, 1))])
  end
end
