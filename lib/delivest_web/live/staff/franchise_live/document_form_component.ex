defmodule DelivestWeb.Staff.FranchiseLive.DocumentFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Franchise

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:body],
      do: {:ok, socket},
      else: {:ok, assign(socket, body: assigns.document.body, error: nil)}
  end

  @impl true
  def handle_event("validate", %{"document" => %{"body" => body}}, socket) do
    {:noreply, assign(socket, body: body)}
  end

  def handle_event("save", %{"document" => %{"body" => body}}, socket) do
    socket.assigns.current_staff
    |> Franchise.update_document(socket.assigns.document.kind, body)
    |> reply(assign(socket, body: body))
  end

  def handle_event("reset", _params, socket) do
    socket.assigns.current_staff
    |> Franchise.reset_document(socket.assigns.document.kind)
    |> reply(socket)
  end

  defp reply({:ok, _document}, socket) do
    send(self(), {__MODULE__, :saved})
    {:noreply, socket}
  end

  defp reply({:error, %Ecto.Changeset{} = changeset}, socket) do
    {:noreply, assign(socket, error: changeset.errors |> hd() |> elem(1) |> translate_error())}
  end

  defp reply({:error, :forbidden}, socket) do
    {:noreply,
     put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <form
        id="document-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full gap-3"
      >
        <p class="text-xs text-base-content/60">
          {gettext("Lines starting with «## » become headings. Placeholders:")}
          <code :for={key <- Franchise.placeholders()} class="mr-1">{"{{#{key}}}"}</code>
        </p>
        <textarea
          name="document[body]"
          id="document-body"
          class="textarea w-full flex-1 min-h-96 font-mono text-sm"
          phx-debounce="300"
        >{@body}</textarea>
        <p :if={@error} class="text-sm text-error">{@error}</p>

        <div class="shrink-0 pt-3 border-t border-base-200 flex items-center gap-3">
          <button
            :if={@document.custom}
            type="button"
            class="btn btn-ghost text-warning"
            phx-click="reset"
            phx-target={@myself}
            data-confirm={gettext("Replace the text with the default template?")}
          >
            {gettext("Restore template")}
          </button>
          <span class="flex-1"></span>
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </form>
    </div>
    """
  end
end
