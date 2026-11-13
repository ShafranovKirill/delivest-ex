defmodule DelivestWeb.Staff.MarketingLive.Navigation do
  use DelivestWeb, :html

  alias Delivest.{Features, Gateway, Identity}

  def global_area_links?(staff, branches), do: available?(staff, branches)

  def available?(staff, branches) do
    Identity.can?(staff, "franchise.update") or
      (Identity.can?(staff, "marketing.read") and
         Features.enabled?("marketing_policies", :franchise)) or
      Enum.any?(branches, fn branch ->
        Identity.authorize(staff, "stocks.read", branch.id) == :ok or
          Identity.authorize(staff, "promotions.read", branch.id) == :ok or
          (Identity.authorize(staff, "statistics.read", branch.id) == :ok and
             Features.enabled?("analytics_links", {:branch, branch.id}))
      end)
  end

  attr :staff, :any, required: true
  attr :branches, :list, required: true
  attr :branch, :any, default: nil
  attr :active, :atom, required: true
  attr :part, :atom, default: :all, values: [:all, :areas, :branches]

  def navigation(assigns) do
    branches = Delivest.Repo.preload(assigns.branches, :info)
    selected = Enum.find(branches, &(&1.id == (assigns.branch && assigns.branch.id)))

    area_paths =
      Map.new([:stocks, :promotions, :links], fn area ->
        {area, area_path(assigns.staff, branches, selected, area)}
      end)

    assigns =
      assigns
      |> assign(:branches, branches)
      |> assign(:selected, selected)
      |> assign(:area_paths, area_paths)

    ~H"""
    <div id={if @part != :branches, do: "marketing-navigation"} class="space-y-3">
      <div :if={@part != :branches} class="flex flex-nowrap gap-2">
        <.link
          :if={
            Identity.can?(@staff, "marketing.read") and
              Features.enabled?("marketing_policies", :franchise)
          }
          navigate={global_path(:policies, @selected)}
          class={["btn btn-sm", @active == :policies && "btn-primary"]}
          aria-current={@active == :policies && "page"}
        >{gettext("Marketing policies")}</.link>
        <.link
          :if={@area_paths.stocks}
          navigate={@area_paths.stocks}
          class={["btn btn-sm", @active == :stocks && "btn-primary"]}
          aria-current={@active == :stocks && "page"}
        >{gettext("Banners")}</.link>
        <.link
          :if={@area_paths.promotions}
          navigate={@area_paths.promotions}
          class={["btn btn-sm", @active == :promotions && "btn-primary"]}
          aria-current={@active == :promotions && "page"}
        >{gettext("Discounts & promo codes")}</.link>
        <.link
          :if={
            Identity.can?(@staff, "franchise.update") or
              Enum.any?(@branches, fn branch ->
                Identity.authorize(@staff, "promotions.read", branch.id) == :ok and
                  Gateway.own?(branch, :loyalty)
              end)
          }
          navigate={global_path(:bonuses, @selected)}
          class={["btn btn-sm", @active == :loyalty && "btn-primary"]}
          aria-current={@active == :loyalty && "page"}
        >{gettext("Bonuses")}</.link>
        <.link
          :if={@area_paths.links}
          navigate={@area_paths.links}
          class={["btn btn-sm", @active == :links && "btn-primary"]}
          aria-current={@active == :links && "page"}
        >{gettext("Advertising links")}</.link>
      </div>
      <div
        :if={@part != :areas and length(@branches) > 0}
        id="marketing-branches"
        class="flex flex-wrap items-center gap-2 text-sm"
      >
        <span>{gettext("Branch")}</span>
        <.link
          :for={branch <- @branches}
          :if={branch_target(@staff, branch, @active)}
          navigate={branch_target(@staff, branch, @active)}
          class={["btn btn-xs", @selected && @selected.id == branch.id && "btn-primary"]}
        >{branch.name}</.link>
      </div>
      <p
        :if={@part != :areas and is_nil(@selected)}
        id="marketing-choose-branch"
        class="text-sm text-base-content/60"
      >
        {gettext("Choose a branch for branch marketing settings.")}
      </p>
    </div>
    """
  end

  defp area_path(staff, branches, selected, area) do
    if selected && branch_target(staff, selected, area) do
      branch_target(staff, selected, area)
    else
      if Enum.any?(branches, &branch_target(staff, &1, area)),
        do: ~p"/staff/marketing?#{%{section: area}}"
    end
  end

  defp global_path(:policies, nil), do: ~p"/staff/marketing/policies"
  defp global_path(:bonuses, nil), do: ~p"/staff/marketing/bonuses"

  defp global_path(:policies, branch),
    do: ~p"/staff/marketing/policies?#{%{branch: branch.slug}}"

  defp global_path(:bonuses, branch),
    do: ~p"/staff/marketing/bonuses?#{%{branch: branch.slug}}"

  defp branch_target(staff, branch, :stocks) do
    if Identity.authorize(staff, "stocks.read", branch.id) == :ok,
      do: ~p"/staff/b/#{branch}/stocks"
  end

  defp branch_target(staff, branch, :promotions) do
    if Identity.authorize(staff, "promotions.read", branch.id) == :ok,
      do: ~p"/staff/b/#{branch}/promotions"
  end

  defp branch_target(staff, branch, :loyalty) do
    if Identity.authorize(staff, "promotions.read", branch.id) == :ok and
         Gateway.own?(branch, :loyalty),
       do: ~p"/staff/b/#{branch}/loyalty"
  end

  defp branch_target(staff, branch, :links) do
    if Identity.authorize(staff, "statistics.read", branch.id) == :ok and
         Features.enabled?("analytics_links", {:branch, branch.id}),
       do: ~p"/staff/b/#{branch}/advertising-links"
  end

  defp branch_target(staff, branch, _active) do
    if branch_target(staff, branch, :stocks) || branch_target(staff, branch, :promotions) ||
         branch_target(staff, branch, :links),
       do: ~p"/staff/marketing?#{%{branch: branch.slug}}"
  end
end
