defmodule DelivestWeb.KitchenAccess do
  @moduledoc """
  Shared rules and messages for opening the kitchen screen.

  The availability itself lives in `Delivest.Oms.Kitchen.available?/2`; this
  module only turns it into the page decision.
  """

  use Gettext, backend: DelivestWeb.Gettext
  use DelivestWeb, :verified_routes

  alias Delivest.{Identity, Oms.Kitchen}

  def available?(staff, branch), do: Kitchen.available?(staff, branch)

  def message(branch_or_id) do
    case Kitchen.unavailable_reason(branch_or_id) do
      :crm -> gettext("The kitchen works in the CRM and is not available in the app")
      _reason -> gettext("The kitchen is off in the branch settings")
    end
  end

  def fallback_path(staff, branch) do
    if Kitchen.account?(staff) or not Identity.has_branch_access?(staff, branch.id),
      do: "/staff/branches/select",
      else: ~p"/staff/b/#{branch}/dashboard"
  end
end
