defmodule DelivestWeb.StudioLive.MediaUploadComponent do
  @moduledoc """
  Reusable S3 direct-upload LiveComponent modal.
  Ничего не знает о продуктах, заказах или пользователях конкретного домена.
  """
  use DelivestWeb, :live_component
  alias Delivest.Media

  @impl true
  def update(assigns, socket) do
    upload_type = Map.get(assigns, :upload_type, "image")
    settings = Media.Config.upload_settings(upload_type)

    max_files = Map.get(assigns, :max_files, settings.max_entries)
    current_count = Map.get(assigns, :current_file_count, 0)
    remaining = max(1, max_files - current_count)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:is_private, fn -> false end)
     |> assign(accept_str: settings.description)
     |> assign(max_entries: remaining)
     |> allow_upload(:media,
       accept: settings.accept,
       max_entries: remaining,
       max_file_size: settings.max_size,
       external: &presign_upload/2
     )}
  end

  defp presign_upload(entry, socket) do
    group_name = socket.assigns[:media_group_name] || "general"
    context = socket.assigns[:context] || "general"
    is_private = socket.assigns.is_private

    case Media.prepare_upload(group_name, context, entry.client_name, is_private: is_private) do
      {:ok, meta} ->
        meta_with_uploader = Map.put(meta, :uploader, "S3")
        {:ok, meta_with_uploader, socket}

      {:error, _} ->
        {:error, %{reason: gettext("Could not generate upload URL")}, socket}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  def handle_event("save", _params, socket) do
    user_id = socket.assigns[:user_id]
    file_context = socket.assigns[:context] || "general"
    is_private = socket.assigns.is_private

    results =
      consume_uploaded_entries(socket, :media, fn meta, entry ->
        file_attrs = %{
          "bucket" => meta.bucket,
          "key" => meta.key,
          "original_name" => entry.client_name,
          "mime_type" => entry.client_type,
          "size" => entry.client_size,
          "context" => file_context,
          "is_private" => is_private,
          "owner_id" => user_id
        }

        case Media.create_file(file_attrs) do
          {:ok, media_file} ->
            {:ok, {:ok, media_file}}

          {:error, err} ->
            {:ok, {:error, err}}
        end
      end)

    send(self(), {__MODULE__, {:saved, results}})

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_all_entries", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.media.entries, socket, fn entry, acc ->
        cancel_upload(acc, :media, entry.ref)
      end)

    {:noreply, socket}
  end

  @doc false
  defp error_to_string(:too_large), do: gettext("File is too large")
  defp error_to_string(:not_accepted), do: gettext("Unacceptable file type")
  defp error_to_string(:too_many_files), do: gettext("Too many files")
  defp error_to_string(_), do: gettext("Upload error")

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal
        id="media-upload-modal"
        show={true}
        title={gettext("Upload Media")}
        on_cancel={JS.push("cancel_media_upload")}
      >
        <div>
          <% has_entries = @uploads.media.entries != []

          is_uploading =
            Enum.any?(
              @uploads.media.entries,
              &(&1.progress > 0 and &1.progress < 100 and upload_errors(@uploads.media, &1) == [])
            )

          has_errors = Enum.any?(@uploads.media.entries, &(upload_errors(@uploads.media, &1) != [])) %>

          <form id="upload-form" phx-submit="save" phx-change="validate" phx-target={@myself}>
            <div
              class={[
                "relative border-2 border-dashed rounded-sm transition-all duration-200 group flex flex-col items-center justify-center p-10 text-center",
                if(has_entries,
                  do: "hidden",
                  else: "border-base-300 hover:border-primary/50 hover:bg-base-200/50 bg-base-100"
                )
              ]}
              phx-drop-target={@uploads.media.ref}
            >
              <.live_file_input
                upload={@uploads.media}
                class="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
              />
              <div class="flex items-center justify-center w-16 h-16 bg-primary/10 border border-primary/20 text-primary rounded-sm mb-4 group-hover:scale-105 transition-transform">
                <.icon name="hero-cloud-arrow-up" class="size-8" />
              </div>
              <h4 class="font-black text-lg text-base-content mb-1">
                {gettext("Click or drag files here")}
              </h4>
              <p class="text-sm font-medium text-base-content/50">{@accept_str}</p>
            </div>

            <div :if={has_entries} class="space-y-3 max-h-64 overflow-y-auto">
              <div
                :for={entry <- @uploads.media.entries}
                class="flex flex-col gap-3 p-4 bg-base-200/50 rounded-sm border border-base-300"
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-3 min-w-0">
                    <div class="p-2 bg-base-100 rounded-sm border border-base-200 text-base-content/50 shrink-0">
                      <.icon name="hero-photo" class="size-5" />
                    </div>
                    <div class="truncate">
                      <div class="text-sm font-bold text-base-content truncate">
                        {entry.client_name}
                      </div>
                      <div class="text-xs font-medium text-base-content/50 uppercase tracking-wider">
                        {Float.round(entry.client_size / 1024 / 1024, 2)} MB
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center gap-4 shrink-0">
                    <span :if={entry.progress > 0} class="text-sm font-black text-primary">
                      {entry.progress}%
                    </span>
                    <button
                      type="button"
                      phx-click="cancel_entry"
                      phx-value-ref={entry.ref}
                      phx-target={@myself}
                      class="btn btn-ghost btn-sm btn-square min-h-9 h-9 w-9 text-error hover:bg-error/10"
                      title={gettext("Cancel")}
                    >
                      <.icon name="hero-x-mark" class="size-5" />
                    </button>
                  </div>
                </div>

                <div class="w-full bg-base-300 rounded-sm h-2 overflow-hidden">
                  <div
                    class={[
                      "h-full transition-all duration-300",
                      upload_errors(@uploads.media, entry) != [] && "bg-error",
                      upload_errors(@uploads.media, entry) == [] && "bg-primary"
                    ]}
                    style={"width: #{entry.progress}%"}
                  >
                  </div>
                </div>
                <div
                  :for={err <- upload_errors(@uploads.media, entry)}
                  class="text-error text-xs font-bold flex items-center gap-1"
                >
                  <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
                  {error_to_string(err)}
                </div>
              </div>
            </div>

            <div class="flex flex-col-reverse sm:flex-row justify-end gap-3 mt-8 pt-6 border-t border-base-200">
              <button type="button" phx-click="cancel_media_upload" class="btn btn-outline">
                {gettext("Cancel")}
              </button>

              <button
                :if={has_errors}
                type="button"
                phx-click="clear_all_entries"
                phx-target={@myself}
                class="btn btn-warning btn-outline"
              >
                <.icon name="hero-arrow-path" class="size-4 mr-1" />
                {gettext("Clear Selection")}
              </button>

              <button
                type="submit"
                class="btn btn-primary phx-submit-loading:opacity-70"
                disabled={not has_entries or is_uploading or has_errors}
              >
                <.icon name="hero-arrow-up-tray" class="size-4 mr-2" />
                {if is_uploading, do: gettext("Uploading..."), else: gettext("Upload Files")}
              </button>
            </div>
          </form>
        </div>
      </.modal>
    </div>
    """
  end
end
