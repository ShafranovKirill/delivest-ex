defmodule Delivest.Integrations.StaffAccessTest do
  use Delivest.DataCase, async: true

  alias Delivest.Features
  alias Delivest.Integrations.StaffAccess

  test "registered CRM extension has a switch and unknown providers remain unavailable" do
    assert :test_crm in Enum.map(StaffAccess.providers(), &elem(&1, 0))
    assert "integration_test_crm" in StaffAccess.keys()
    assert StaffAccess.allowed?(:test_crm)
    assert StaffAccess.snapshot()[:test_crm]
    refute Map.has_key?(StaffAccess.snapshot(), :unknown_provider)
    refute StaffAccess.allowed?(:unknown_provider)
    refute StaffAccess.allowed_key?("integration_unknown_provider")

    assert {:ok, _} =
             Features.configure("integration_test_crm", :franchise, false, actor: "test")

    refute StaffAccess.allowed?(:test_crm)
    refute StaffAccess.snapshot()[:test_crm]

    assert {:ok, _} =
             Features.configure("integration_test_crm", :franchise, true, actor: "test")

    assert StaffAccess.allowed?(:test_crm)
    assert StaffAccess.snapshot()[:test_crm]
  end
end
