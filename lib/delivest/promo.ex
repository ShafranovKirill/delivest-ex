defmodule Delivest.Promo do
  alias Delivest.Promo.{
    Codes,
    Context,
    Engine,
    Issuing,
    MenuPrices,
    Promotions,
    Redemptions
  }

  def price(items, context), do: Engine.run(items, Context.new(context))

  defdelegate overlay_menu(categories, branch_id), to: MenuPrices, as: :overlay
  defdelegate redeem(order, result), to: Redemptions, as: :replace

  defdelegate list_promotions(staff, branch_id), to: Promotions, as: :list
  defdelegate list_running_promotions(branch_id), to: Promotions, as: :list_running
  defdelegate list_personal_promotions(branch_id), to: Promotions, as: :list_personal
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
