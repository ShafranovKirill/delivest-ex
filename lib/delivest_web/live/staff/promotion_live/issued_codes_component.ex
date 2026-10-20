defmodule DelivestWeb.Staff.PromotionLive.IssuedCodesComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Identity, Promo}
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  @impl true
  def update(assigns, socket) do
    if socket.assigns[:promotion] && socket.assigns.promotion.id == assigns.promotion.id do
      {:ok, assign(socket, assigns)}
    else
      {:ok,
       socket
       |> assign(assigns)
       |> assign(form: issue_form(%{}), issued: nil)
       |> load_codes()}
    end
  end

  @impl true
  def handle_event("issue", %{"issue" => params}, socket) do
    %{current_staff: staff, promotion: promotion} = socket.assigns

    with {:ok, phone} <- phone(params["phone"]),
         {:ok, code} <- Promo.issue_code_by_phone(staff, promotion, phone, uses(params["uses"])) do
      {:noreply, socket |> assign(form: issue_form(%{}), issued: code) |> load_codes()}
    else
      {:error, :invalid_phone} ->
        {:noreply,
         assign(socket, form: issue_form(params, phone: gettext("Phone must be +7XXXXXXXXXX")))}

      {:error, _reason} ->
        {:noreply,
         assign(socket, form: issue_form(params, phone: gettext("Failed to issue a code")))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    with {:ok, code} <- Promo.get_issued_code(socket.assigns.promotion.branch_id, id),
         {:ok, _code} <- Promo.revoke_code(socket.assigns.current_staff, code) do
      {:noreply, load_codes(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp load_codes(socket) do
    codes = Promo.list_issued_codes(socket.assigns.promotion)

    usage =
      Delivest.Promo.Usage.load([socket.assigns.promotion.id], nil, Enum.map(codes, & &1.id), nil)

    assign(socket, codes: codes, usage: usage)
  end

  defp issue_form(params, errors \\ []) do
    to_form(params,
      as: :issue,
      errors: Enum.map(errors, fn {field, msg} -> {field, {msg, []}} end)
    )
  end

  defp phone(phone) when is_binary(phone) do
    phone = String.replace(phone, ~r/[^\d+]/, "")

    if Regex.match?(Identity.phone_regex(), phone),
      do: {:ok, phone},
      else: {:error, :invalid_phone}
  end

  defp phone(_phone), do: {:error, :invalid_phone}

  defp uses(value) do
    case Integer.parse(to_string(value)) do
      {uses, ""} when uses > 0 -> uses
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.form
        for={@form}
        id="issue-code-form"
        phx-target={@myself}
        phx-submit="issue"
        class="rounded-box border border-base-300 p-3 space-y-2"
      >
        <p class="font-bold text-sm">{gettext("Issue a personal code")}</p>
        <div class="grid grid-cols-3 gap-2">
          <div class="col-span-2">
            <.input
              field={@form[:phone]}
              type="tel"
              label={gettext("Client phone")}
              placeholder="+79991112233"
            />
          </div>
          <.input
            field={@form[:uses]}
            type="number"
            min="1"
            value={@form[:uses].value || 1}
            label={gettext("Uses")}
          />
        </div>
        <button
          type="submit"
          class="btn btn-primary btn-sm w-full"
          phx-disable-with={gettext("Saving...")}
        >
          <.icon name="hero-ticket" class="size-4" /> {gettext("Issue code")}
        </button>
        <div :if={@issued} id="issued-code" class="alert alert-success text-sm">
          <span>
            {gettext("Code for %{client}:", client: @issued.client.phone)}
            <span class="font-mono font-bold text-base select-all">{@issued.code}</span>
          </span>
        </div>
      </.form>

      <div>
        <p class="font-bold text-sm mb-2">{gettext("Issued codes")} ({length(@codes)})</p>
        <p :if={@codes == []} class="text-sm text-base-content/60">
          {gettext("No codes issued yet")}
        </p>
        <ul class="divide-y divide-base-200">
          <li :for={code <- @codes} id={"issued-#{code.id}"} class="py-2 flex items-center gap-3">
            <div class="min-w-0 flex-1">
              <p class="font-mono font-bold">{code.code}</p>
              <p class="text-xs text-base-content/60 truncate">
                <.link navigate={~p"/staff/clients/#{code.client_id}"} class="link link-hover">
                  {code.client.name || code.client.phone}
                </.link>
                · {OrderHelpers.local_datetime(code.inserted_at)}
              </p>
            </div>
            <span class="badge badge-ghost badge-sm shrink-0">
              {Delivest.Promo.Usage.code(@usage, code.id)} / {code.usage_limit || "∞"}
            </span>
            <button
              type="button"
              phx-click="revoke"
              phx-value-id={code.id}
              phx-target={@myself}
              data-confirm={gettext("Revoke this code?")}
              class="btn btn-ghost btn-xs btn-square text-error"
              title={gettext("Revoke")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
