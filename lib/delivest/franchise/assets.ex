defmodule Delivest.Franchise.Assets do
  alias Delivest.Franchise.{Images, Settings}
  alias Delivest.Media

  require Logger

  def store_icon(binary) do
    with {:ok, files} <- Images.icon(binary) do
      dir = "franchise/icon/#{Ecto.UUID.generate()}"

      files
      |> Enum.reduce_while(:ok, fn {name, body, type}, :ok ->
        case put("#{dir}/#{name}", body, type) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
      |> case do
        :ok -> {:ok, dir}
        error -> error
      end
    end
  end

  def store_share_image(binary) do
    with {:ok, jpeg} <- Images.share_image(binary),
         key = "franchise/share/#{Ecto.UUID.generate()}.jpg",
         :ok <- put(key, jpeg, "image/jpeg") do
      {:ok, key}
    end
  end

  def store_logo(binary) do
    with {:ok, png} <- Images.logo(binary),
         key = "franchise/logo/#{Ecto.UUID.generate()}.png",
         :ok <- put(key, png, "image/png") do
      {:ok, key}
    end
  end

  def delete_icon(nil), do: :ok

  def delete_icon(dir) do
    Enum.each(
      ~w(favicon.ico icon-32.png apple-touch-icon.png icon-192.png icon-512.png),
      &delete("#{dir}/#{&1}")
    )
  end

  def delete_share_image(nil), do: :ok
  def delete_share_image(key), do: delete(key)

  def delete_logo(nil), do: :ok
  def delete_logo(key), do: delete(key)

  def icon_url(%Settings{icon_key: nil}, _name), do: nil
  def icon_url(%Settings{icon_key: dir}, name), do: url("#{dir}/#{name}")

  def share_image_url(%Settings{share_image_key: nil}), do: nil
  def share_image_url(%Settings{share_image_key: key}), do: url(key)

  def logo_url(%Settings{logo_key: key}), do: optional_url(key)
  def logo_dark_url(%Settings{logo_dark_key: key}), do: optional_url(key)

  defp optional_url(nil), do: nil
  defp optional_url(key), do: url(key)

  defp url(key) do
    {:ok, url} = Media.generate_public_url(Media.public_bucket(), key)
    url
  end

  defp put(key, body, content_type) do
    Media.public_bucket()
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> ExAws.request()
    |> case do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("[Franchise.Assets] Failed to upload #{key}: #{inspect(reason)}")
        {:error, :storage}
    end
  end

  defp delete(key) do
    case Media.public_bucket() |> ExAws.S3.delete_object(key) |> ExAws.request() do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Franchise.Assets] Failed to delete #{key}: #{inspect(reason)}")
    end
  end
end
