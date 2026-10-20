defmodule DelivestWeb.Staff.PromotionLive.PromotionFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Net, Promo}
  alias Delivest.Promo.{Dsl, Strategy}
  alias DelivestWeb.Staff.PromotionLive.{PromotionHelpers, RulesHelp, RulesText}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form] && socket.assigns[:loaded_id] == assigns.promotion.id do
      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(loaded_id: assigns.promotion.id)
       |> assign_form(Promo.change_promotion(assigns.promotion))}
    end
  end

  @impl true
  def handle_event("validate", %{"promotion" => params}, socket) do
    changeset =
      socket.assigns.promotion
      |> Promo.change_promotion(PromotionHelpers.window_to_utc(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"promotion" => params}, socket) do
    params = PromotionHelpers.window_to_utc(params)

    case save(socket.assigns, params) do
      {:ok, promotion} ->
        send(self(), {__MODULE__, {:saved, promotion}})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp save(%{action: :new} = assigns, params),
    do: Promo.create_promotion(assigns.current_staff, assigns.branch_id, params)

  defp save(assigns, params),
    do: Promo.update_promotion(assigns.current_staff, assigns.promotion, params)

  defp assign_form(socket, changeset) do
    socket
    |> assign(form: to_form(changeset))
    |> assign(
      preview: preview(Ecto.Changeset.get_field(changeset, :rules), socket.assigns.branch_id)
    )
  end

  defp preview(rules, branch_id) do
    case Dsl.parse(rules) do
      {:ok, strategy} -> RulesText.describe(strategy, product_names(strategy, branch_id))
      {:error, _errors} -> nil
    end
  end

  defp rules_placeholder, do: "when subtotal >= 1500\nthen discount 10%"

  defp product_names(strategy, branch_id) do
    branch_id
    |> Net.list_branch_products_by_slugs(Strategy.slugs(strategy))
    |> Map.new(fn {slug, product} -> {slug, product.name} end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="promotion-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto space-y-4">
          <.input field={@form[:name]} type="text" label={gettext("Name")} maxlength="100" />
          <.input
            field={@form[:description]}
            type="textarea"
            rows="2"
            label={gettext("Description for customers")}
            maxlength="500"
          />

          <.input
            field={@form[:kind]}
            type="select"
            label={gettext("Type")}
            options={PromotionHelpers.kind_options()}
            disabled={@action != :new}
          />

          <div :if={to_string(@form[:kind].value) == "public_code"}>
            <.input
              field={@form[:code]}
              type="text"
              label={gettext("Promo code")}
              placeholder="SUMMER2026"
              maxlength="32"
              class="input w-full font-mono uppercase"
            />
          </div>

          <p
            :if={to_string(@form[:kind].value) == "personal_code"}
            class="text-xs text-base-content/60"
          >
            {gettext("Unique codes are issued to clients from the promotion list or the client page.")}
          </p>

          <div class="space-y-2">
            <.input
              field={@form[:rules]}
              type="textarea"
              rows="6"
              label={gettext("Rules")}
              class="textarea w-full font-mono text-sm"
              spellcheck="false"
              placeholder={rules_placeholder()}
            />

            <div
              :if={@preview}
              id="rules-preview"
              class="rounded-box border border-success/30 bg-success/5 p-3 text-sm space-y-1"
            >
              <p :if={@preview.condition}>
                <span class="font-bold">{gettext("When")}:</span> {@preview.condition}
              </p>
              <p :if={!@preview.condition} class="text-base-content/60">{gettext("Always")}</p>
              <p>
                <span class="font-bold">{gettext("Then")}:</span> {Enum.join(@preview.effects, "; ")}
              </p>
            </div>

            <RulesHelp.render_help />
          </div>

          <div class="divider text-xs font-bold uppercase text-base-content/50 my-1">
            {gettext("Limits")}
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3">
            <.input
              field={@form[:starts_at]}
              type="datetime-local"
              label={gettext("Starts")}
              value={PromotionHelpers.local_input(@form[:starts_at].value)}
            />
            <.input
              field={@form[:ends_at]}
              type="datetime-local"
              label={gettext("Ends")}
              value={PromotionHelpers.local_input(@form[:ends_at].value)}
            />
            <.input field={@form[:usage_limit]} type="number" min="1" label={gettext("Total uses")} />
            <.input
              field={@form[:per_client_limit]}
              type="number"
              min="1"
              label={gettext("Uses per client")}
            />
          </div>
          <p class="text-xs text-base-content/60">
            {gettext("Leave empty for no limit. Per-client limits need the client's phone.")}
          </p>

          <div class="divider text-xs font-bold uppercase text-base-content/50 my-1">
            {gettext("Compatibility")}
          </div>

          <.input field={@form[:priority]} type="number" label={gettext("Priority")} />
          <.input
            field={@form[:combinable]}
            type="checkbox"
            label={gettext("Combines with other combinable promotions")}
          />
          <p class="text-xs text-base-content/60">
            {gettext(
              "An entered promo code always goes first. Automatic promotions follow by priority; a non-combinable one blocks the rest."
            )}
          </p>

          <.input field={@form[:enabled]} type="checkbox" label={gettext("Enabled")} />
        </div>

        <div class="shrink-0 pt-4 mt-4 border-t border-base-200 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
