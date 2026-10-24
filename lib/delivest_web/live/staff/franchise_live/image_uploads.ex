defmodule DelivestWeb.Staff.FranchiseLive.ImageUploads do
  use DelivestWeb, :html

  import Phoenix.LiveView

  alias Delivest.Media

  def allow(socket, names, progress) do
    settings = Media.Config.upload_settings("image")

    Enum.reduce(names, socket, fn name, acc ->
      allow_upload(acc, name,
        accept: settings.accept,
        max_entries: 1,
        max_file_size: settings.max_size,
        auto_upload: true,
        progress: progress
      )
    end)
  end

  def read(socket, entry),
    do: consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

  def drop_invalid(socket, names, on_error) do
    Enum.reduce(names, socket, fn name, acc ->
      upload = acc.assigns.uploads[name]

      Enum.reduce(upload.entries, acc, fn entry, acc ->
        case upload_errors(upload, entry) do
          [] ->
            acc

          [error | _rest] ->
            on_error.(upload_error_text(error))
            cancel_upload(acc, name, entry.ref)
        end
      end)
    end)
  end

  def error_text(:invalid_image), do: gettext("Could not read the image")
  def error_text(:forbidden), do: gettext("You don't have permission to perform this action.")
  def error_text(_reason), do: gettext("Could not save the image, try again")

  defp upload_error_text(:too_large), do: gettext("File is too large")
  defp upload_error_text(:not_accepted), do: gettext("Unsupported file type")
  defp upload_error_text(_error), do: gettext("Upload failed")

  attr :upload, :any, required: true
  attr :image, :string, required: true
  attr :present, :boolean, required: true
  attr :target, :any, required: true
  attr :hint, :string, required: true

  def image_input(assigns) do
    assigns = assign(assigns, entry: List.first(assigns.upload.entries))

    ~H"""
    <div class="space-y-1.5" phx-drop-target={@upload.ref}>
      <.live_file_input upload={@upload} class="hidden" />
      <div class="flex flex-wrap items-center gap-2">
        <label for={@upload.ref} class="btn btn-sm btn-outline">
          <.icon name="hero-arrow-up-tray" class="size-4" />
          {if @present, do: gettext("Replace"), else: gettext("Upload")}
        </label>
        <button
          :if={@present}
          type="button"
          class="btn btn-sm btn-ghost text-error"
          phx-click="remove"
          phx-value-image={@image}
          phx-target={@target}
          data-confirm={gettext("Are you sure?")}
        >
          <.icon name="hero-trash" class="size-4" /> {gettext("Remove")}
        </button>
        <span :if={@entry && !@entry.done?} class="text-xs text-base-content/60">
          {@entry.progress}%
        </span>
      </div>
      <p class="text-xs text-base-content/50">{@hint}</p>
      <p :for={error <- upload_errors(@upload)} class="text-xs text-error">
        {upload_error_text(error)}
      </p>
    </div>
    """
  end
end
