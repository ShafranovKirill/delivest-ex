defmodule Delivest.Net.Products do
  import Ecto.Query

  alias Delivest.Net.Product
  alias Ecto.Multi
  alias Delivest.{Repo, Identity, Relations}

  def list_staff_products_for_branch(staff, branch_id, params \\ %{}, opts \\ []) do
    if Identity.can?(staff, "products.read") do
      product_ids = Relations.list_target_ids("Branch", branch_id, "Product")

      Product
      |> where([p], p.id in ^product_ids)
      |> where([p], is_nil(p.deleted_at))
      |> maybe_preload_query(opts)
      |> Flop.validate_and_run(params, for: Product)
    else
      {:error, :forbidden}
    end
  end

  def create_product(staff, branch_id, attrs) do
    if Identity.can?(staff, "products.create") do
      Multi.new()
      |> Multi.insert(:product, Product.changeset(%Product{}, attrs))
      |> Multi.run(:relation_branch, fn repo, %{product: product} ->
        case Relations.create_relation(
               repo,
               "Branch",
               branch_id,
               "Product",
               product.id,
               %{}
             ) do
          {:ok, relation} -> {:ok, relation}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{product: created_product}} ->
          invalidate_menu_cache(branch_id)
          {:ok, created_product}

        {:error, _failed_operation, error, _changes_so_far} ->
          {:error, error}
      end
    else
      {:error, :forbidden}
    end
  end

  def prepare_product_media_upload(staff, filename) do
    if Identity.can?(staff, "products.create") or Identity.can?(staff, "products.update") do
      bucket = Application.get_env(:delivest, Delivest.Media)[:bucket] || "delivest"

      unique_filename = "#{Ecto.UUID.generate()}-#{filename}"
      key = "products/#{unique_filename}"

      case Delivest.Media.generate_upload_url(bucket, key) do
        {:ok, presigned_url} ->
          local_url = "/media/#{key}"

          meta = %{
            uploader: "S3",
            url: presigned_url,
            url_for_saved_entry: local_url,
            bucket: bucket,
            key: key
          }

          {:ok, meta}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :forbidden}
    end
  end

  def create_product_media_file(staff, meta, entry) do
    if Identity.can?(staff, "products.create") or Identity.can?(staff, "products.update") do
      file_attrs = %{
        "bucket" => meta.bucket,
        "key" => meta.key,
        "original_name" => entry.client_name,
        "mime_type" => entry.client_type,
        "size" => entry.client_size,
        "context" => :product,
        "owner_id" => staff.id
      }

      Delivest.Media.create_file(file_attrs)
    else
      {:error, :forbidden}
    end
  end

  def update_product(staff, %Product{} = updateble_product, attrs) do
    if Identity.can?(staff, "products.update") do
      updateble_product
      |> Product.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_product} ->
          branch_id = get_product_branch_id(updated_product.id)
          invalidate_menu_cache(branch_id)
          {:ok, updated_product}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  def soft_delete_product(staff, %Product{} = product) do
    if Identity.can?(staff, "products.delete") do
      with {:ok, deleted_product} <-
             product
             |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
             |> Repo.update() do
        branch_id = get_product_branch_id(product.id)
        invalidate_menu_cache(branch_id)
        {:ok, deleted_product}
      end
    else
      {:error, :forbidden}
    end
  end

  defp get_product_branch_id(product_id) do
    Relations.list_source_ids("Product", product_id, "Branch")
    |> List.first()
  end

  defp invalidate_menu_cache(branch_id) when not is_nil(branch_id) do
    Cachex.del(:menu_cache, branch_id)
  end

  defp invalidate_menu_cache(_), do: :ok

  defp maybe_preload_query(query, opts) do
    case Keyword.get(opts, :preload) do
      nil -> query
      preloads -> preload(query, ^preloads)
    end
  end
end
