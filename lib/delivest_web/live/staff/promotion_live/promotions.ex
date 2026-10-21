defmodule DelivestWeb.Staff.PromotionLive.Promotions do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Net, Promo}
  alias Delivest.Promo.{Dsl, Promotion, Strategy, Usage}
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  alias DelivestWeb.Staff.PromotionLive.{
    IssuedCodesComponent,
    ProductSaleFormComponent,
    PromotionFormComponent,
    PromotionHelpers,
    RulesText
  }

  on_mount {DelivestWeb.Hooks.Permission, "promotions.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(branch_id: socket.assigns.current_branch.id, promotion: nil, to_delete: nil)
     |> load()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params),
    do: assign(socket, page_title: gettext("Discounts & promo codes"), promotion: nil)

  defp apply_action(socket, :new, _params) do
    if can?(socket, "promotions.create"),
      do:
        assign(socket,
          page_title: gettext("New promotion"),
          promotion: %Promotion{branch_id: socket.assigns.branch_id}
        ),
      else: deny(socket)
  end

  defp apply_action(socket, :sale, _params) do
    if can?(socket, "promotions.create"),
      do: assign(socket, page_title: gettext("Product discount"), promotion: nil),
      else: deny(socket)
  end

  defp apply_action(socket, action, %{"id" => id}) when action in [:edit, :codes] do
    with true <- can?(socket, "promotions.update"),
         {:ok, promotion} <-
           Promo.get_promotion(socket.assigns.current_staff, socket.assigns.branch_id, id) do
      assign(socket, page_title: title(action, promotion), promotion: promotion)
    else
      _ -> deny(socket)
    end
  end

  defp title(:edit, promotion), do: gettext("Edit «%{name}»", name: promotion.name)
  defp title(:codes, promotion), do: gettext("Codes «%{name}»", name: promotion.name)

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    with_promotion(socket, id, &Promo.toggle_promotion(socket.assigns.current_staff, &1))
  end

  def handle_event("delete_click", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.promotions, &(&1.id == id)) do
      nil -> {:noreply, socket}
      promotion -> {:noreply, assign(socket, to_delete: promotion)}
    end
  end

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, to_delete: nil)}

  def handle_event("confirm_delete", _params, %{assigns: %{to_delete: promotion}} = socket) do
    case Promo.delete_promotion(socket.assigns.current_staff, promotion) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Promotion deleted"))
         |> assign(to_delete: nil)
         |> load()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Failed to delete promotion"))
         |> assign(to_delete: nil)}
    end
  end

  @impl true
  def handle_info({component, {:saved, _promotion}}, socket)
      when component in [PromotionFormComponent, ProductSaleFormComponent] do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Promotion saved"))
     |> load()
     |> push_patch(to: ~p"/staff/promotions")}
  end

  defp with_promotion(socket, id, fun) do
    with %Promotion{} = promotion <- Enum.find(socket.assigns.promotions, &(&1.id == id)),
         {:ok, _} <- fun.(promotion) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action failed"))}
    end
  end

  defp load(socket) do
    case Promo.list_promotions(socket.assigns.current_staff, socket.assigns.branch_id) do
      {:ok, promotions} ->
        assign(socket,
          promotions: promotions,
          summaries: summaries(promotions, socket.assigns.branch_id),
          usage: Promo.promotions_usage(promotions),
          now: DateTime.utc_now()
        )

      {:error, _} ->
        assign(socket, promotions: [], summaries: %{}, usage: %Usage{}, now: DateTime.utc_now())
    end
  end

  defp summaries(promotions, branch_id) do
    strategies =
      for promotion <- promotions,
          {:ok, strategy} <- [Dsl.parse(promotion.rules)],
          into: %{},
          do: {promotion.id, strategy}

    names =
      branch_id
      |> Net.list_branch_products_by_slugs(
        strategies
        |> Map.values()
        |> Enum.flat_map(&Strategy.slugs/1)
        |> Enum.uniq()
      )
      |> Map.new(fn {slug, product} -> {slug, product.name} end)

    Map.new(strategies, fn {id, strategy} -> {id, RulesText.describe(strategy, names)} end)
  end

  defp deny(socket) do
    socket
    |> put_flash(:error, gettext("You don't have permission to perform this action."))
    |> push_patch(to: ~p"/staff/promotions")
  end

  defp can?(socket, permission), do: Identity.can?(socket.assigns.current_staff, permission)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-5xl mx-auto">
      <.page_header
        title={gettext("Discounts & promo codes")}
        subtitle={gettext("Automatic promotions, sale prices, public and personal promo codes.")}
      >
        <:actions>
          <.link
            :if={Identity.can?(@current_staff, "promotions.create")}
            patch={~p"/staff/promotions/new"}
            class="btn btn-outline"
            id="new-promotion"
          >
            <.icon name="hero-plus" class="size-5" /> {gettext("New promotion")}
          </.link>
          <.link
            :if={Identity.can?(@current_staff, "promotions.create")}
            patch={~p"/staff/promotions/sale"}
            class="btn btn-primary"
            id="new-sale"
          >
            <.icon name="hero-tag" class="size-5" /> {gettext("Product discount")}
          </.link>
        </:actions>
      </.page_header>

      <div
        :if={@promotions == []}
        class="rounded-box border border-dashed border-base-300 p-10 text-center text-base-content/60"
      >
        <.icon name="hero-receipt-percent" class="size-10 opacity-40" />
        <p class="mt-2">{gettext("No promotions yet")}</p>
        <p class="mt-1 text-sm">
          {gettext("To put a product on sale, press «Product discount».")}
        </p>
      </div>

      <div id="promotions" class="space-y-3">
        <div
          :for={promotion <- @promotions}
          id={"promotion-#{promotion.id}"}
          class="p-4 bg-base-100 rounded-box border border-base-200 shadow-sm flex flex-col sm:flex-row sm:items-center gap-3"
        >
          <div class="size-10 rounded-full bg-primary/10 text-primary flex items-center justify-center shrink-0">
            <.icon name={PromotionHelpers.kind_icon(promotion.kind)} class="size-5" />
          </div>

          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-bold truncate">{promotion.name}</span>
              <% state = PromotionHelpers.state(promotion, @now) %>
              <span class={["badge badge-sm", PromotionHelpers.state_class(state)]}>
                {PromotionHelpers.state_label(state)}
              </span>
              <span class="badge badge-ghost badge-sm">{PromotionHelpers.kind_label(promotion.kind)}</span>
              <span :if={promotion.code} class="badge badge-outline badge-sm font-mono">{promotion.code}</span>
              <span :if={promotion.combinable} class="badge badge-ghost badge-sm">{gettext(
                "combinable"
              )}</span>
            </div>
            <% summary = @summaries[promotion.id] %>
            <p :if={summary} class="mt-1 text-sm text-base-content/70 line-clamp-2">
              <span :if={summary.condition}>{summary.condition} → </span>{Enum.join(
                summary.effects,
                "; "
              )}
            </p>
            <pre
              :if={!summary}
              class="mt-1 text-xs text-base-content/60 font-mono whitespace-pre-wrap line-clamp-2"
            >{promotion.rules}</pre>
            <p class="mt-1 text-xs text-base-content/50">
              {gettext("Used")}: {PromotionHelpers.usage_label(
                Usage.total(@usage, promotion.id),
                promotion.usage_limit
              )}
              <span :if={promotion.starts_at || promotion.ends_at}>
                · {OrderHelpers.local_datetime(promotion.starts_at)} — {OrderHelpers.local_datetime(
                  promotion.ends_at
                )}
              </span>
            </p>
          </div>

          <div class="flex items-center gap-1 shrink-0">
            <input
              :if={Identity.can?(@current_staff, "promotions.update")}
              type="checkbox"
              class="toggle toggle-success toggle-sm"
              checked={promotion.enabled}
              phx-click="toggle"
              phx-value-id={promotion.id}
              title={gettext("Enabled")}
            />
            <.link
              :if={
                promotion.kind == :personal_code and
                  Identity.can?(@current_staff, "promotions.update")
              }
              patch={~p"/staff/promotions/#{promotion.id}/codes"}
              class="btn btn-sm btn-ghost btn-square text-primary"
              title={gettext("Personal codes")}
            >
              <.icon name="hero-ticket" class="size-5" />
            </.link>
            <.link
              :if={Identity.can?(@current_staff, "promotions.update")}
              patch={~p"/staff/promotions/#{promotion.id}/edit"}
              class="btn btn-sm btn-ghost btn-square text-info"
              title={gettext("Edit")}
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
            <button
              :if={Identity.can?(@current_staff, "promotions.delete")}
              type="button"
              phx-click="delete_click"
              phx-value-id={promotion.id}
              class="btn btn-sm btn-ghost btn-square text-error"
              title={gettext("Delete")}
            >
              <.icon name="hero-trash" class="size-5" />
            </button>
          </div>
        </div>
      </div>

      <.slide_over
        id="promotion-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/promotions")}
      >
        <.live_component
          :if={@promotion && @live_action in [:new, :edit]}
          module={PromotionFormComponent}
          id={@promotion.id || :new}
          action={@live_action}
          promotion={@promotion}
          branch_id={@branch_id}
          current_staff={@current_staff}
          patch={~p"/staff/promotions"}
        />
      </.slide_over>

      <.slide_over
        id="sale-slideover"
        show={@live_action == :sale}
        title={@page_title}
        on_close={JS.patch(~p"/staff/promotions")}
      >
        <.live_component
          :if={@live_action == :sale}
          module={ProductSaleFormComponent}
          id="product-sale"
          branch_id={@branch_id}
          current_staff={@current_staff}
          patch={~p"/staff/promotions"}
        />
      </.slide_over>

      <.slide_over
        id="codes-slideover"
        show={@live_action == :codes}
        title={@page_title}
        on_close={JS.patch(~p"/staff/promotions")}
      >
        <.live_component
          :if={@promotion && @live_action == :codes}
          module={IssuedCodesComponent}
          id={"codes-#{@promotion.id}"}
          promotion={@promotion}
          current_staff={@current_staff}
        />
      </.slide_over>

      <.modal
        id="delete-promotion-modal"
        show={@to_delete != nil}
        title={gettext("Delete promotion")}
        description={gettext("The promotion stops working immediately. Order history keeps it.")}
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
