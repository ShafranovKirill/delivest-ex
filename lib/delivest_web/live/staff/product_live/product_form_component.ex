defmodule DelivestWeb.Staff.ProductLive.ProductFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Net, Media}
  alias Delivest.Net.Product

  import Ecto.Changeset

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    current_product_id = socket.assigns[:product] && socket.assigns[:product].id
    new_product_id = assigns.product && assigns.product.id

    if is_nil(socket.assigns[:form]) || current_product_id != new_product_id ||
         socket.assigns[:action] != assigns.action do
      product = assigns.product
      current_staff = assigns.current_staff
      branch_id = assigns.branch_id

      form_data = if product && product.id, do: product, else: %Product{}
      changeset = Product.changeset(form_data, %{})

      category_options =
        case Net.Categories.list_staff_categories_for_branch(current_staff, branch_id) do
          categories when is_list(categories) ->
            no_category_option = {gettext("Without category"), ""}

            mapped_categories = Enum.map(categories, &{&1.name, &1.id})

            [no_category_option | mapped_categories]

          _ ->
            [{gettext("Without category"), ""}]
        end

      current_media = if product, do: Media.get_file(product.media_id), else: nil

      socket =
        socket
        |> assign(:form, to_form(changeset))
        |> assign(:category_options, category_options)
        |> assign(:current_media, current_media)
        |> allow_upload(:photo,
          accept: ~w(.jpg .jpeg .png .webp),
          max_entries: 1,
          max_file_size: 5 * 1024 * 1024
        )

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    base_form =
      if socket.assigns.product.id,
        do: socket.assigns.product,
        else: %Product{}

    normalized_params = normalize_params(params)

    changeset =
      base_form
      |> Product.changeset(normalized_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  @impl true
  def handle_event("save", %{"product" => params}, socket) do
    case consume_uploaded_photo(socket) do
      {:ok, media_id} when not is_nil(media_id) ->
        params = Map.put(params, "media_id", media_id)
        save_product_with_params(socket, socket.assigns.action, params)

      {:ok, nil} ->
        save_product_with_params(socket, socket.assigns.action, params)

      {:error, reason} ->
        socket = put_flash(socket, :error, "#{gettext("File upload error:")} #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  defp normalize_params(params) do
    case params["category_id"] do
      "" -> Map.put(params, "category_id", nil)
      _ -> params
    end
  end

  defp consume_uploaded_photo(socket) do
    try do
      result =
        consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
          bucket = Application.get_env(:delivest, Delivest.Media)[:bucket] || "delivest"
          unique_filename = "#{Ecto.UUID.generate()}-#{entry.client_name}"
          key = "products/#{unique_filename}"

          file_binary = File.read!(path)

          case ExAws.S3.put_object(bucket, key, file_binary, content_type: entry.client_type)
               |> ExAws.request() do
            {:ok, _} ->
              file_attrs = %{
                "bucket" => bucket,
                "key" => key,
                "original_name" => entry.client_name,
                "mime_type" => entry.client_type,
                "size" => entry.client_size,
                "context" => :product,
                "owner_id" => socket.assigns.current_staff.id
              }

              case Media.create_file(file_attrs) do
                {:ok, media_file} ->
                  {:ok, media_file.id}

                {:error, changeset} ->
                  raise "Failed to create media file: #{inspect(changeset)}"
              end

            {:error, error} ->
              raise "S3 upload failed: #{inspect(error)}"
          end
        end)

      case result do
        [media_id | _] -> {:ok, media_id}
        [] -> {:ok, nil}
      end
    rescue
      exception -> {:error, exception}
    end
  end

  defp save_product_with_params(socket, :edit, params) do
    params = Map.put_new(params, "category_id", nil)
    normalized_params = normalize_params(params)

    socket.assigns.product
    |> Product.changeset(normalized_params)
    |> Map.put(:action, :update)
    |> do_save_product(socket, :edit)
  end

  defp save_product_with_params(socket, :new, params) do
    params = Map.put_new(params, "category_id", nil)
    normalized_params = normalize_params(params)

    %Product{}
    |> Product.changeset(normalized_params)
    |> Map.put(:action, :insert)
    |> do_save_product(socket, :new)
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    params = to_params(changeset)

    case Net.Products.update_product(
           socket.assigns.current_staff,
           socket.assigns.product,
           params
         ) do
      {:ok, product} ->
        notify_parent({:saved, product})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    params = to_params(changeset)
    branch_id = socket.assigns.branch_id

    case Net.Products.create_product(
           socket.assigns.current_staff,
           branch_id,
           params
         ) do
      {:ok, product} ->
        notify_parent({:saved, product})
        {:noreply, socket}

      {:error, changeset_or_reason} ->
        changeset =
          case changeset_or_reason do
            %Ecto.Changeset{} = cs ->
              cs

            _ ->
              Product.changeset(socket.assigns.product || %Product{}, params)
              |> Map.put(:action, :insert)
          end

        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: false} = changeset, socket, _action) do
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  defp to_params(changeset) do
    data = apply_changes(changeset)

    data
    |> Map.take([:name, :price, :description, :is_active, :external_id, :category_id, :media_id])
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="product-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Product Information")}
          </div>

          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-bold">{gettext("Product Image")}</span>
            </label>

            <div class="flex items-center gap-4">
              <div class="avatar">
                <div class="w-24 h-24 rounded-box bg-base-200 border border-base-300 flex items-center justify-center overflow-hidden">
                  <%= if length(@uploads.photo.entries) > 0 do %>
                    <% [entry | _] = @uploads.photo.entries %>
                    <.live_img_preview entry={entry} class="w-full h-full object-cover" />
                  <% else %>
                    <%= if @current_media && !is_nil(@current_media.key) do %>
                      <% {:ok, download_url} =
                        Media.generate_download_url(@current_media.bucket, @current_media.key) %>
                      <img src={download_url} class="w-full h-full object-cover" />
                    <% else %>
                      <span class="text-xs text-base-content/40">{gettext("No image")}</span>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <div class="flex-1">
                <.live_file_input
                  upload={@uploads.photo}
                  class="file-input file-input-bordered file-input-sm w-full"
                />
                <label class="label">
                  <span class="label-text-alt text-base-content/60">
                    {gettext("PNG, JPG, WEBP up to 5MB")}
                  </span>
                </label>

                <%= for err <- upload_errors(@uploads.photo) do %>
                  <p class="text-error text-xs mt-1">{error_to_string(err)}</p>
                <% end %>
              </div>
            </div>
          </div>

          <.input field={@form[:name]} type="text" label={gettext("Name")} required />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:price]} type="number" label={gettext("Price")} required />

            <.input
              field={@form[:category_id]}
              type="select"
              label={gettext("Category")}
              options={@category_options}
              prompt={gettext("Select a category...")}
            />
          </div>

          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("Enter product description...")}
          />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 items-center pt-2">
            <.input field={@form[:external_id]} type="text" label={gettext("External ID")} />

            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-4 pt-6">
                <input
                  type="hidden"
                  name={@form[:is_active].name}
                  value="false"
                />
                <input
                  type="checkbox"
                  name={@form[:is_active].name}
                  value="true"
                  checked={@form[:is_active].value == true}
                  class="checkbox checkbox-primary"
                />
                <span class="label-text font-bold">{gettext("Active")}</span>
              </label>
            </div>
          </div>
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp error_to_string(:too_large), do: gettext("File is too large")
  defp error_to_string(:too_many_files), do: gettext("Too many files")
  defp error_to_string(:not_accepted), do: gettext("Unacceptable file format")
  defp error_to_string(_), do: gettext("Upload error")
end
