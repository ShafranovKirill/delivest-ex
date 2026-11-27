defmodule Delivest.Oms.Orders.StopGuard do
  alias Delivest.Integrations.Crm
  alias Delivest.Identity.Branch
  alias Delivest.Net.{ComboAvailability, Modifiers, Products, Stops}
  alias Delivest.Promo.Result
  alias Delivest.Repo

  def check(branch_id, pricing, opts \\ [])
  def check(nil, _pricing, _opts), do: {:ok, :available}

  def check(branch_id, %Result{lines: lines}, opts) do
    ids = Enum.map(lines, & &1.product_id)

    with {:ok, :available} <- Stops.ensure_available(branch_id, ids),
         :ok <- check_combos(branch_id, lines, ids, opts) do
      {:ok, :available}
    end
  end

  defp check_combos(_branch_id, _lines, [], _opts), do: :ok

  defp check_combos(branch_id, lines, ids, opts) do
    products = Products.list_branch_cart_products_by_ids(branch_id, ids)
    combo_lines = Enum.filter(lines, &match?(%{is_combo: true}, products[&1.product_id]))

    if combo_lines == [] do
      :ok
    else
      branch = Repo.get(Branch, branch_id)
      branch = if branch, do: Repo.preload(branch, :info)

      if opts[:crm] || (branch && Crm.provider_for(branch, Keyword.get(opts, :source, "app"))) do
        {:error, :combo_requires_delivest}
      else
        groups = Modifiers.for_products(Enum.map(combo_lines, & &1.product_id))
        unavailable = ComboAvailability.unavailable_component_ids(branch_id, groups)

        if Enum.all?(combo_lines, fn line ->
             ComboAvailability.selected_available?(
               Map.get(groups, line.product_id, []),
               line.modifiers,
               unavailable
             )
           end),
           do: :ok,
           else: {:error, :product_unavailable}
      end
    end
  end
end
