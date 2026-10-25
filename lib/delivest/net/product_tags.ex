defmodule Delivest.Net.ProductTags do
  import Ecto.Query

  alias Delivest.{Audit, Identity, Media, Repo}
  alias Delivest.Net.{Product, ProductTag, TagIcons}
  alias Ecto.Changeset
  alias Vix.Vips.{Image, Operation}

  use Gettext, backend: DelivestWeb.Gettext

  @icon_size 64

  def list_tags do
    ProductTag
    |> order_by([t], asc: t.order, asc: t.inserted_at)
    |> Repo.all()
  end

  def get_tag(id), do: Repo.get(ProductTag, id)

  def change_tag(%ProductTag{} = tag, attrs \\ %{}), do: ProductTag.changeset(tag, attrs)

  def usage_counts do
    "SELECT tag, count(*) FROM products, unnest(tags) AS tag WHERE deleted_at IS NULL GROUP BY tag"
    |> Repo.query!()
    |> Map.get(:rows)
    |> Map.new(fn [tag, count] -> {tag, count} end)
  end

  def menu_tags do
    Map.new(list_tags(), &{&1.id, %{id: &1.id, name: &1.name, icon_url: icon_url(&1)}})
  end

  def icon_url(%ProductTag{icon_key: key}) when is_binary(key) do
    {:ok, url} = Media.generate_public_url(Media.public_bucket(), key)
    url
  end

  def icon_url(%ProductTag{icon: icon}) when is_binary(icon), do: TagIcons.url(icon)
  def icon_url(_tag), do: nil

  def create_tag(staff, attrs, upload \\ nil) do
    authorized(staff, fn ->
      %ProductTag{order: next_order()}
      |> ProductTag.changeset(attrs)
      |> save(upload)
      |> Audit.track(staff, "product_tag.created")
    end)
  end

  def update_tag(staff, %ProductTag{} = tag, attrs, upload \\ nil) do
    authorized(staff, fn ->
      tag
      |> ProductTag.changeset(attrs)
      |> save(upload)
      |> Audit.track(staff, "product_tag.updated")
    end)
  end

  def delete_tag(staff, %ProductTag{} = tag) do
    authorized(staff, fn ->
      Repo.transaction(fn ->
        Repo.update_all(
          from(p in Product,
            where: ^tag.id in p.tags,
            update: [set: [tags: fragment("array_remove(?, ?)", p.tags, ^tag.id)]]
          ),
          []
        )

        Repo.delete!(tag)
      end)
      |> tap(fn _result ->
        delete_icon(tag.icon_key)
        clear_caches()
      end)
      |> Audit.track(staff, "product_tag.deleted")
    end)
  end

  defp save(changeset, upload) do
    previous_key = changeset.data.icon_key

    with {:ok, changeset} <- put_icon(changeset, upload),
         {:ok, tag} <- changeset |> ProductTag.require_icon() |> Repo.insert_or_update() do
      if previous_key != tag.icon_key, do: delete_icon(previous_key)
      clear_caches()
      {:ok, tag}
    else
      {:error, %Changeset{} = changeset} ->
        delete_icon(Changeset.get_change(changeset, :icon_key))
        {:error, changeset}

      error ->
        error
    end
  end

  defp put_icon(changeset, nil) do
    if Changeset.get_change(changeset, :icon),
      do: {:ok, Changeset.put_change(changeset, :icon_key, nil)},
      else: {:ok, changeset}
  end

  defp put_icon(changeset, binary) when is_binary(binary) do
    key = "product-tags/#{Ecto.UUID.generate()}.png"

    with {:ok, png} <- shrink(binary),
         :ok <- put(key, png) do
      {:ok, changeset |> Changeset.put_change(:icon_key, key) |> Changeset.put_change(:icon, nil)}
    else
      {:error, :invalid_image} ->
        {:error, Changeset.add_error(changeset, :icon, gettext("Could not read the image"))}

      {:error, _reason} ->
        {:error,
         Changeset.add_error(changeset, :icon, gettext("Could not save the image, try again"))}
    end
  end

  def shrink(binary) do
    with {:ok, thumb} <-
           Operation.thumbnail_buffer(binary, @icon_size,
             height: @icon_size,
             size: :VIPS_SIZE_DOWN
           ),
         {:ok, png} <- Image.write_to_buffer(thumb, ".png[strip,palette,Q=70,compression=9]") do
      {:ok, png}
    else
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  defp put(key, body) do
    Media.public_bucket()
    |> ExAws.S3.put_object(key, body, content_type: "image/png")
    |> ExAws.request()
    |> case do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_icon(nil), do: :ok

  defp delete_icon(key) do
    Media.public_bucket() |> ExAws.S3.delete_object(key) |> ExAws.request()
    :ok
  end

  defp next_order do
    (Repo.one(from t in ProductTag, select: max(t.order)) || 0.0) + 1.0
  end

  defp clear_caches do
    Cachex.clear(:menu_cache)
    Cachex.clear(:cart_cache)
  end

  defp authorized(staff, fun) do
    if Identity.can?(staff, "products.update"), do: fun.(), else: {:error, :forbidden}
  end
end
