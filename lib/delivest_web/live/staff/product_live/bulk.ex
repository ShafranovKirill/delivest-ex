defmodule DelivestWeb.Staff.ProductLive.Bulk do
  use DelivestWeb, :live_view

  alias Delivest.{Media, Net}
  alias Delivest.Integrations.Crm
  alias DelivestWeb.Staff.ProductLive.BulkRows

  on_mount {DelivestWeb.Hooks.Permission, "products.create"}

  @initial_rows 5

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: gettext("Bulk add products"),
        branch_id: socket.assigns.current_branch.id,
        rows: [],
        errors: %{},
        show_errors: false
      )
      |> add_rows(@initial_rows)

    {:ok, socket}
  end

  @impl true
  def handle_event("change", params, socket),
    do: {:noreply, socket |> apply_changes(params) |> validate()}

  def handle_event("paste", %{"row" => row_id, "column" => column, "text" => text}, socket) do
    pasted = BulkRows.paste(text, column)
    {:noreply, socket |> fill_rows(String.to_integer(row_id), pasted) |> validate()}
  end

  def handle_event("add_rows", %{"count" => count}, socket) do
    {:noreply, add_rows(socket, String.to_integer(count))}
  end

  def handle_event("remove_row", %{"id" => id}, socket) do
    id = String.to_integer(id)
    row = Enum.find(socket.assigns.rows, &(&1.id == id))

    socket =
      socket
      |> cancel_photos(row)
      |> disallow_upload(upload_name(id))
      |> assign(rows: Enum.reject(socket.assigns.rows, &(&1.id == id)))

    {:noreply, validate(socket)}
  end

  def handle_event("cancel_photo", %{"id" => id, "ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, upload_name(String.to_integer(id)), ref)}
  end

  def handle_event("save", params, socket),
    do: {:noreply, socket |> apply_changes(params) |> validate() |> save()}

  defp apply_changes(socket, params) do
    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case get_in(params, ["rows", to_string(row.id)]) do
          nil -> row
          values -> %{row | values: Map.merge(row.values, Map.take(values, BulkRows.columns()))}
        end
      end)

    assign(socket, rows: rows)
  end

  defp save(socket) do
    filled = filled_rows(socket.assigns)
    socket = assign(socket, show_errors: true)

    cond do
      filled == [] ->
        put_flash(socket, :error, gettext("Fill in at least one product"))

      Enum.any?(filled, &Map.has_key?(socket.assigns.errors, &1.id)) ->
        put_flash(socket, :error, gettext("Fix the highlighted cells"))

      Enum.any?(filled, &uploading?(socket, &1)) ->
        put_flash(socket, :error, gettext("Wait until the photos finish uploading"))

      true ->
        create(socket, filled)
    end
  end

  defp with_crm_id(attrs, provider) do
    case Map.pop(attrs, "external_id") do
      {nil, attrs} -> attrs
      {crm_id, attrs} -> Map.put(attrs, "crm_ids", %{to_string(provider) => crm_id})
    end
  end

  defp create(socket, rows) do
    staff = socket.assigns.current_staff

    provider = Crm.default_provider(socket.assigns.branch_id)

    products =
      Enum.map(rows, fn row ->
        {attrs, _errors} = BulkRows.validate(row.values)

        attrs
        |> with_crm_id(provider)
        |> Map.put("media_id", consume_photo(socket, row, staff))
      end)

    case Net.import_products(staff, socket.assigns.branch_id, products) do
      {:ok, created} ->
        socket
        |> put_flash(:info, gettext("Products added: %{count}", count: length(created)))
        |> push_navigate(to: ~p"/staff/products")

      {:error, :forbidden} ->
        put_flash(socket, :error, gettext("Permission denied"))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("Failed to add products"))
    end
  end

  defp consume_photo(socket, row, staff) do
    socket
    |> consume_uploaded_entries(upload_name(row.id), fn meta, entry ->
      Media.create_file(%{
        "bucket" => meta.bucket,
        "key" => meta.key,
        "original_name" => entry.client_name,
        "mime_type" => entry.client_type,
        "size" => entry.client_size,
        "context" => "product",
        "is_private" => false,
        "owner_id" => staff.id
      })
      |> then(&{:ok, &1})
    end)
    |> Enum.find_value(fn
      {:ok, file} -> file.id
      _error -> nil
    end)
  end

  defp filled_rows(assigns),
    do: Enum.reject(assigns.rows, &(BulkRows.blank?(&1.values) and photo(assigns, &1) == nil))

  defp validate(socket) do
    errors =
      socket.assigns
      |> filled_rows()
      |> Enum.flat_map(fn row ->
        case BulkRows.validate(row.values) do
          {_attrs, errors} when errors == %{} -> []
          {_attrs, errors} -> [{row.id, errors}]
        end
      end)
      |> Map.new()

    assign(socket, errors: errors)
  end

  defp fill_rows(socket, start_id, pasted) do
    rows = socket.assigns.rows
    start = Enum.find_index(rows, &(&1.id == start_id)) || length(rows)
    missing = start + length(pasted) - length(rows)
    socket = if missing > 0, do: add_rows(socket, missing), else: socket

    rows =
      socket.assigns.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        case Enum.at(pasted, index - start) do
          values when index >= start and is_map(values) ->
            %{row | values: Map.merge(row.values, values)}

          _ ->
            row
        end
      end)

    assign(socket, rows: rows)
  end

  defp add_rows(socket, count) do
    taken = MapSet.new(socket.assigns.rows, & &1.id)
    room = BulkRows.max_rows() - length(socket.assigns.rows)

    ids =
      Stream.iterate(1, &(&1 + 1))
      |> Stream.reject(&MapSet.member?(taken, &1))
      |> Enum.take(max(0, min(count, room)))

    Enum.reduce(ids, socket, fn id, acc ->
      settings = Media.Config.upload_settings("image")

      acc
      |> allow_upload(upload_name(id),
        accept: settings.accept,
        max_entries: 1,
        max_file_size: settings.max_size,
        auto_upload: true,
        external: &presign/2
      )
      |> update(:rows, &(&1 ++ [%{id: id, values: BulkRows.blank_values()}]))
    end)
  end

  defp presign(entry, socket) do
    case Media.prepare_upload(socket.assigns.branch_id, "product", entry.client_name,
           public: true
         ) do
      {:ok, meta} -> {:ok, Map.put(meta, :uploader, "S3"), socket}
      {:error, _reason} -> {:error, %{reason: gettext("Could not generate upload URL")}, socket}
    end
  end

  defp cancel_photos(socket, nil), do: socket

  defp cancel_photos(socket, row) do
    name = upload_name(row.id)

    Enum.reduce(socket.assigns.uploads[name].entries, socket, fn entry, acc ->
      cancel_upload(acc, name, entry.ref)
    end)
  end

  defp upload_name(id), do: String.to_atom("bulk_photo_#{id}")

  defp photo(assigns, row), do: List.first(assigns.uploads[upload_name(row.id)].entries)

  defp uploading?(socket, row) do
    case photo(socket.assigns, row) do
      nil -> false
      entry -> not entry.done?
    end
  end

  defp cell_error(assigns, row, column) do
    if assigns.show_errors or not BulkRows.blank?(row.values),
      do: get_in(assigns.errors, [row.id, column])
  end

  defp error_lines(rows, errors) do
    for {row, index} <- Enum.with_index(rows, 1), Map.has_key?(errors, row.id) do
      details =
        Enum.map_join(errors[row.id], "; ", fn {column, message} ->
          "#{BulkRows.label(column)} — #{message}"
        end)

      gettext("Row %{index}", index: index) <> ": " <> details
    end
  end

  defp column_class("name"), do: "min-w-48"
  defp column_class("description"), do: "min-w-64"
  defp column_class("category"), do: "min-w-36"
  defp column_class("external_id"), do: "min-w-28"
  defp column_class(_column), do: "min-w-24"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Bulk add products")}
        subtitle={
          gettext(
            "Paste a table from Excel or Google Sheets into any cell (Ctrl+V) or fill it in by hand. Add a photo with the button in the last column."
          )
        }
      >
        <:actions>
          <.link navigate={~p"/staff/products"} class="btn btn-ghost">
            <.icon name="hero-arrow-left" class="size-5" /> {gettext("Back to products")}
          </.link>
        </:actions>
      </.page_header>

      <.form
        for={%{}}
        id="bulk-products"
        phx-change="change"
        phx-submit="save"
        class="space-y-4"
      >
        <div
          id="bulk-table"
          phx-hook="BulkPaste"
          class="overflow-x-auto rounded-box border border-base-300 bg-base-100"
        >
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="w-10">#</th>
                <th :for={column <- BulkRows.columns()} class={column_class(column)}>
                  {BulkRows.label(column)}<span :if={BulkRows.required?(column)} class="text-error">*</span>
                </th>
                <th class="w-20 text-center">{gettext("Photo")}</th>
                <th class="w-10"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{row, index} <- Enum.with_index(@rows, 1)} id={"bulk-row-#{row.id}"}>
                <td class="text-base-content/50 tabular-nums">{index}</td>
                <td :for={column <- BulkRows.columns()} class="p-1">
                  <% error = cell_error(assigns, row, column) %>
                  <input
                    type="text"
                    id={"bulk-#{row.id}-#{column}"}
                    name={"rows[#{row.id}][#{column}]"}
                    value={row.values[column]}
                    data-row={row.id}
                    data-column={column}
                    phx-debounce="300"
                    title={error}
                    class={[
                      "input input-sm w-full",
                      error && "input-error bg-error/5"
                    ]}
                  />
                </td>
                <td class="p-1">
                  <.photo_cell
                    upload={@uploads[upload_name(row.id)]}
                    row_id={row.id}
                  />
                </td>
                <td class="p-1">
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-error"
                    phx-click="remove_row"
                    phx-value-id={row.id}
                    title={gettext("Remove row")}
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            class="btn btn-sm btn-outline"
            phx-click="add_rows"
            phx-value-count="1"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Add row")}
          </button>
          <button type="button" class="btn btn-sm btn-ghost" phx-click="add_rows" phx-value-count="10">
            {gettext("+10 rows")}
          </button>
        </div>

        <div
          :if={@show_errors and @errors != %{}}
          id="bulk-errors"
          class="rounded-box border border-error/40 bg-error/5 p-3 text-sm text-error space-y-1"
        >
          <p :for={line <- error_lines(@rows, @errors)}>{line}</p>
        </div>

        <div class="sticky bottom-0 z-10 -mx-4 sm:mx-0 flex items-center justify-between gap-3 border-t border-base-300 bg-base-100/95 backdrop-blur px-4 py-3 sm:rounded-box sm:border">
          <span class="text-sm text-base-content/70">
            {gettext("Products to add: %{count}", count: length(filled_rows(assigns)))}
          </span>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            <.icon name="hero-check" class="size-5" /> {gettext("Save all")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :upload, :any, required: true
  attr :row_id, :integer, required: true

  defp photo_cell(assigns) do
    assigns = assign(assigns, entry: List.first(assigns.upload.entries))

    ~H"""
    <div class="flex justify-center">
      <.live_file_input upload={@upload} class="hidden" />
      <div :if={@entry} class="relative size-12">
        <.live_img_preview entry={@entry} class="size-12 rounded-lg object-cover" />
        <div
          :if={!@entry.done?}
          class="absolute inset-0 rounded-lg bg-base-100/70 flex items-center justify-center text-xs font-bold"
        >
          {@entry.progress}%
        </div>
        <button
          type="button"
          class="absolute -top-1.5 -right-1.5 btn btn-circle btn-xs btn-error"
          phx-click="cancel_photo"
          phx-value-id={@row_id}
          phx-value-ref={@entry.ref}
          title={gettext("Remove photo")}
        >
          <.icon name="hero-x-mark" class="size-3" />
        </button>
        <p
          :for={error <- upload_errors(@upload, @entry)}
          class="absolute top-full mt-1 w-28 -left-8 text-[10px] text-error text-center"
        >
          {upload_error_text(error)}
        </p>
      </div>

      <label
        :if={!@entry}
        for={@upload.ref}
        class="size-12 rounded-lg border-2 border-dashed border-base-300 flex items-center justify-center cursor-pointer text-base-content/40 hover:border-primary hover:text-primary transition-colors"
        title={gettext("Upload photo")}
      >
        <.icon name="hero-camera" class="size-5" />
      </label>
    </div>
    """
  end

  defp upload_error_text(:too_large), do: gettext("File is too large")
  defp upload_error_text(:not_accepted), do: gettext("Unsupported file type")
  defp upload_error_text(_error), do: gettext("Upload failed")
end
