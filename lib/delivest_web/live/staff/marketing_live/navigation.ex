defmodule DelivestWeb.Staff.MarketingLive.Navigation do
  use DelivestWeb, :html

  alias Delivest.{Features, Gateway, Identity}

  def available?(staff, branches) do
    available_section?(staff, branches, nil, :hub)
  end

  def available_section?(staff, branches, _branch, :hub) do
    (Identity.can?(staff, "marketing.read") and
       Features.enabled?("marketing_policies", :franchise)) or
      Enum.any?(
        [:stocks, :promotions, :loyalty, :links],
        &available_section?(staff, branches, nil, &1)
      )
  end

  def available_section?(staff, branches, branch, section) do
    candidates = if branch, do: [branch], else: branches
    Enum.any?(candidates, &(not is_nil(branch_target(staff, &1, section))))
  end

  attr :staff, :any, required: true
  attr :branches, :list, required: true
  attr :branch, :any, default: nil
  attr :active, :atom, required: true
  attr :part, :atom, default: :all, values: [:all, :areas, :branches]

  def navigation(assigns) do
    branches = Delivest.Repo.preload(assigns.branches, :info)
    selected = Enum.find(branches, &(&1.id == (assigns.branch && assigns.branch.id)))

    assigns =
      assigns
      |> assign(:branches, branches)
      |> assign(:selected, selected)

    ~H"""
    <div id="marketing-branch-picker" class="space-y-3">
      <div
        :if={length(@branches) > 0}
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
        :if={is_nil(@selected)}
        id="marketing-choose-branch"
        class="text-sm text-base-content/60"
      >
        {gettext("Choose a branch for branch marketing settings.")}
      </p>
    </div>
    """
  end

  defp branch_target(staff, branch, :policies) do
    if Identity.can?(staff, "marketing.read") and
         Features.enabled?("marketing_policies", :franchise),
       do: ~p"/staff/marketing/policies?#{%{branch: branch.slug}}"
  end

  defp branch_target(staff, branch, :stocks) do
    if Identity.authorize(staff, "stocks.read", branch.id) == :ok and
         Features.enabled?("stocks", {:branch, branch.id}),
       do: ~p"/staff/b/#{branch}/stocks"
  end

  defp branch_target(staff, branch, :promotions) do
    if Identity.authorize(staff, "promotions.read", branch.id) == :ok and
         Features.enabled?("promotions", {:branch, branch.id}),
       do: ~p"/staff/b/#{branch}/promotions"
  end

  defp branch_target(staff, branch, :loyalty) do
    if Identity.authorize(staff, "promotions.read", branch.id) == :ok and
         Gateway.own?(branch, :loyalty) and Features.enabled?("loyalty", {:branch, branch.id}),
       do: ~p"/staff/b/#{branch}/loyalty"
  end

  defp branch_target(staff, branch, :links) do
    if Identity.authorize(staff, "statistics.read", branch.id) == :ok and
         Features.enabled?("analytics_links", {:branch, branch.id}),
       do: ~p"/staff/b/#{branch}/advertising-links"
  end

  defp branch_target(staff, branch, _active) do
    if branch_target(staff, branch, :stocks) || branch_target(staff, branch, :promotions) ||
         branch_target(staff, branch, :loyalty) || branch_target(staff, branch, :links) ||
         branch_target(staff, branch, :policies),
       do: ~p"/staff/marketing?#{%{branch: branch.slug}}"
  end
end
