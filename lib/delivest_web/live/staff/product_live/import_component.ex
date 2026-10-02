defmodule DelivestWeb.Staff.ProductLive.ImportComponent do
  use DelivestWeb, :live_component
  alias Delivest.Net.Products.ProductImportWorker

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> allow_upload(:csv_file,
       accept: ~w(.csv),
       max_entries: 1,
       # 10 МБ
       max_file_size: 10 * 1024 * 1024
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    [file_path] =
      consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
        dest = Path.join(System.tmp_dir!(), "import_#{Ecto.UUID.generate()}.csv")
        File.cp!(path, dest)
        {:ok, dest}
      end)

    current_staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id

    # Ставим задачу в Oban
    %{file_path: file_path, staff_id: current_staff.id, branch_id: branch_id}
    |> ProductImportWorker.new()
    |> Oban.insert()

    # Уведомляем родительский LiveView
    send(self(), {__MODULE__, {:queued}})

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-4 space-y-2">
        <h3 class="text-lg font-bold">{gettext("Mass Product Import")}</h3>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Download the template, fill it out, and upload it. Processing will run in the background."
          )}
        </p>
        <div class="flex items-center gap-4 pt-2">
          <a href="/templates/products_template.csv" download class="btn btn-outline btn-sm">
            <.icon name="hero-arrow-down-tray" class="size-4 mr-1" />
            {gettext("Download Template")}
          </a>
        </div>
      </div>

      <.form for={%{}} phx-submit="save" phx-change="validate" phx-target={@myself}>
        <div class="form-control w-full py-4">
          <label class="label">
            <span class="label-text font-bold">{gettext("Select CSV file")}</span>
          </label>
          <.live_file_input upload={@uploads.csv_file} class="file-input file-input-bordered w-full" />
        </div>

        <div class="modal-action">
          <button
            type="submit"
            class="btn btn-primary"
            disabled={Enum.empty?(@uploads.csv_file.entries)}
          >
            {gettext("Start Import")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
