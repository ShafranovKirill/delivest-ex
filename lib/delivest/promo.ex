defmodule Delivest.Promo do
  alias Delivest.Features

  alias Delivest.Promo.{
    Codes,
    Context,
    Engine,
    Issuing,
    MenuPrices,
    Promotions,
    Redemptions
  }

  def price(items, context) do
    context = Context.new(context)

    context =
      if Features.enabled?("promotions", {:branch, context.branch_id}) do
        context
      else
        %{context | compiled_promotions: [], product_snapshot: %{}, code: nil}
      end

    Engine.run(items, context)
  end

  defdelegate overlay_menu(categories, branch_id), to: MenuPrices, as: :overlay
  defdelegate overlay_menu_fresh(categories, branch_id), to: MenuPrices, as: :overlay_fresh
  defdelegate redeem(order, result), to: Redemptions, as: :replace

  defdelegate list_promotions(staff, branch_id), to: Promotions, as: :list

  def list_running_promotions(branch_id),
    do:
      if(Features.enabled?("promotions", {:branch, branch_id}),
        do: Promotions.list_running(branch_id),
        else: []
      )

  def list_personal_promotions(branch_id),
    do:
      if(Features.enabled?("promotions", {:branch, branch_id}),
        do: Promotions.list_personal(branch_id),
        else: []
      )

  defdelegate promotions_usage(promotions), to: Promotions, as: :usage
  defdelegate get_promotion(staff, branch_id, id), to: Promotions, as: :get
  defdelegate change_promotion(promotion, attrs \\ %{}), to: Promotions, as: :change
  defdelegate create_promotion(staff, branch_id, attrs), to: Promotions, as: :create
  defdelegate update_promotion(staff, promotion, attrs), to: Promotions, as: :update
  defdelegate toggle_promotion(staff, promotion), to: Promotions, as: :toggle
  defdelegate delete_promotion(staff, promotion), to: Promotions, as: :delete

  defdelegate list_issued_codes(promotion), to: Codes, as: :list_issued
  defdelegate list_client_codes(client_id, branch_id), to: Codes, as: :list_for_client
  defdelegate issue_code(staff, promotion, client, uses), to: Issuing, as: :issue
  defdelegate issue_code_by_phone(staff, promotion, phone, uses), to: Issuing, as: :issue_by_phone
  defdelegate get_issued_code(branch_id, id), to: Issuing, as: :get_issued
  defdelegate revoke_code(staff, code), to: Issuing, as: :revoke
end
