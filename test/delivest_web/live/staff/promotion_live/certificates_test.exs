defmodule DelivestWeb.Staff.PromotionLive.CertificatesTest do
  use DelivestWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Delivest.Factory

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad.Settings
  alias Delivest.Promo.Promotion
  alias Delivest.Repo

  test "a public promo code requires manual check before saving a Frontpad binding", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Settings{api_key: "secret"}
      }
    })

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")
    assert has_element?(lv, "#promotion-crm-certificate select[name='certificate[provider]']")

    form = %{
      promotion: %{
        name: "Скидка",
        kind: "public_code",
        code: "CERT10"
      },
      certificate: %{provider: "frontpad", code: "CERT10"}
    }

    lv
    |> form("#promotion-form",
      promotion: %{kind: "public_code"},
      certificate: %{provider: "frontpad"}
    )
    |> render_change()

    lv
    |> form("#promotion-form",
      promotion: %{name: "", code: ""},
      certificate: %{provider: "frontpad", code: "CERT10"}
    )
    |> render_submit()

    assert has_element?(lv, "#promotion-reward-error.text-error")
    assert has_element?(lv, "#promotion_name")
    assert has_element?(lv, "#promotion_code")
    assert has_element?(lv, "#promotion-crm-certificate .text-error", "Сначала проверьте")

    lv |> form("#promotion-form", form) |> render_change()
    html = lv |> form("#promotion-form", form) |> render_submit()
    assert html =~ "Сначала проверьте номер сертификата"
    refute Repo.get_by(Promotion, name: "Скидка")

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"result" => "success", "sale" => "10"})
    end)

    lv
    |> element("#promotion-crm-certificate button[phx-click=check_certificate]")
    |> render_click()

    assert has_element?(lv, "#promotion-certificate-result", "10%")
    assert has_element?(lv, "#promotion-certificate-result", "Добавьте награду")

    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()

    lv
    |> form("#promotion-form", Map.put(form, :builder, %{effects: %{"0" => %{value: "10"}}}))
    |> render_submit()

    assert Repo.get_by!(Promotion, name: "Скидка").crm_certificate == %{
             "provider" => "frontpad",
             "code" => "CERT10",
             "type" => "percent",
             "sale" => 10
           }
  end

  test "switching to personal codes clears a previously checked certificate", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Settings{api_key: "secret"}
      }
    })

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"result" => "success", "sale" => "10"})
    end)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")
    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()

    lv
    |> form("#promotion-form", certificate: %{provider: "frontpad"})
    |> render_change()

    lv
    |> form("#promotion-form",
      promotion: %{name: "Personal", code: "CERT10"},
      certificate: %{provider: "frontpad", code: "CERT10"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_change()

    lv
    |> element("#promotion-crm-certificate button[phx-click=check_certificate]")
    |> render_click()

    assert has_element?(lv, "#promotion-certificate-result")
    lv |> form("#promotion-form", promotion: %{kind: "personal_code"}) |> render_change()
    refute has_element?(lv, "#promotion-crm-certificate")

    lv
    |> form("#promotion-form",
      promotion: %{name: "Personal", kind: "personal_code"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_submit()

    assert Repo.get_by!(Promotion, name: "Personal").crm_certificate == nil
  end

  test "switching to automatic clears a checked certificate and saves site rules", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Settings{api_key: "secret-auto"}
      }
    })

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      Req.Test.json(conn, %{"result" => "success", "sale" => "10"})
    end)

    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})
    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/promotions/new/full")
    lv |> element("#add-effect button[phx-value-type=percent]") |> render_click()
    lv |> form("#promotion-form", certificate: %{provider: "frontpad"}) |> render_change()

    lv
    |> form("#promotion-form",
      promotion: %{name: "Automatic", code: "CERT10"},
      certificate: %{provider: "frontpad", code: "CERT10"},
      builder: %{effects: %{"0" => %{value: "10"}}}
    )
    |> render_change()

    lv
    |> element("#promotion-crm-certificate button[phx-click=check_certificate]")
    |> render_click()

    assert has_element?(lv, "#promotion-certificate-result")
    lv |> form("#promotion-form", promotion: %{kind: "automatic"}) |> render_change()
    refute has_element?(lv, "#promotion-crm-certificate")

    lv
    |> form("#promotion-form", promotion: %{name: "Automatic", kind: "automatic"})
    |> render_submit()

    assert %Promotion{kind: :automatic, crm_certificate: nil, rules: "then discount 10%"} =
             Repo.get_by!(Promotion, name: "Automatic")
  end

  test "integration page checks only an entered certificate number", %{conn: conn} do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    conn = init_test_session(conn, %{"staff_id" => staff.id, "active_branch_id" => branch.id})

    Req.Test.stub(Delivest.HTTP.Client, fn _conn ->
      flunk("an empty certificate number must not call Frontpad")
    end)

    {:ok, lv, _} = live(conn, ~p"/staff/b/#{branch}/integrations/frontpad")
    lv |> element("button[phx-value-tab=certificates]") |> render_click()
    assert has_element?(lv, "#frontpad-certificates")

    lv
    |> form("#frontpad-certificates form", certificate: %{code: ""})
    |> render_submit()

    assert has_element?(lv, "#frontpad-certificates .alert-error", "Укажите номер сертификата")
  end
end
