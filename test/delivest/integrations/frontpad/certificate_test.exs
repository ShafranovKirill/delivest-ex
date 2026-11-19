defmodule Delivest.Integrations.Frontpad.CertificateTest do
  use Delivest.DataCase, async: true

  import Delivest.Factory

  alias Delivest.Integrations.Frontpad.Api
  alias Delivest.Integrations.Crm.Certificates
  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Frontpad.Settings
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Promo.Promotions
  alias Delivest.Repo

  test "checks one number with a form POST and normalizes each certificate benefit" do
    for {response, expected} <- [
          {%{"result" => "success", "sale" => "10"}, %{type: :percent, sale: 10}},
          {%{"result" => "success", "amount" => "250.50"}, %{type: :amount, amount: 25_050}},
          {%{"result" => "success", "product_id" => "0001", "name" => "Ролл", "price" => "0"},
           %{type: :product, product_id: "0001", name: "Ролл", price: 0}}
        ] do
      Req.Test.stub(Delivest.HTTP.Client, fn conn ->
        assert conn.method == "POST"
        assert conn.query_string == "get_certificate"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert URI.decode_query(body) == %{"secret" => "test-secret", "certificate" => "CODE1"}
        Req.Test.json(conn, response)
      end)

      assert {:ok, expected} == Api.get_certificate("test-secret", "CODE1")
    end
  end

  test "reports invalid and malformed certificates without accepting partial numeric values" do
    for {response, error} <- [
          {%{"result" => "error", "error" => "invalid_certificate"},
           {:frontpad, "invalid_certificate"}},
          {%{"result" => "success", "sale" => "10oops"}, :invalid_certificate_response},
          {%{"result" => "success", "sale" => %{"bad" => "value"}},
           :invalid_certificate_response},
          {%{"result" => "success", "amount" => "250oops"}, :invalid_certificate_response},
          {%{"result" => "success"}, :invalid_certificate_response}
        ] do
      Req.Test.stub(Delivest.HTTP.Client, &Req.Test.json(&1, response))
      assert {:error, error} == Api.get_certificate("test-secret", "CODE1")
    end
  end

  test "promotion service rejects forged certificate bindings and ignores unsanctioned snapshots" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)

    attrs = %{
      "kind" => "public_code",
      "name" => "Проверка",
      "code" => "CERT10",
      "rules" => "then discount 10%",
      "crm_certificate" => %{"provider" => "frontpad", "code" => "FORGED"}
    }

    assert {:ok, promotion} = Promotions.create(staff, branch.id, attrs)
    assert promotion.crm_certificate == nil

    assert {:error, :invalid_certificate_binding} =
             Promotions.create(staff, branch.id, Map.put(attrs, "crm_certificate_token", "fake"))

    assert {:error, :invalid_certificate_binding} =
             Promotions.create(
               staff,
               branch.id,
               attrs |> Map.delete("kind") |> Map.put("crm_certificate_token", "fake")
             )

    assert {:error, :invalid_certificate_binding} =
             Promotions.update(staff, %{promotion | kind: :personal_code}, %{
               "kind" => "public_code",
               "crm_certificate_token" => "fake"
             })
  end

  test "a manually verified certificate can be bound, kept, removed, and cannot cross branches" do
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    branch = insert(:branch)
    other_branch = insert(:branch)

    Repo.insert!(%BranchInfo{
      branch_id: branch.id,
      crm: %BranchSettings{
        enabled: true,
        provider: :frontpad,
        frontpad: %Settings{api_key: "secret"}
      }
    })

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert URI.decode_query(body)["certificate"] == "CERT10"
      Req.Test.json(conn, %{"result" => "success", "sale" => "10"})
    end)

    assert {:ok, snapshot, token} =
             Certificates.verify(staff, branch.id, "frontpad", "CERT10", "promotions.create")

    assert snapshot == %{
             "provider" => "frontpad",
             "code" => "CERT10",
             "type" => "percent",
             "sale" => 10
           }

    assert {:error, :invalid_certificate_binding} = Certificates.binding(other_branch.id, token)

    attrs = %{
      "kind" => "public_code",
      "name" => "Проверка",
      "code" => "CERT10",
      "rules" => "then discount 10%",
      "crm_certificate_token" => token
    }

    assert {:ok, promotion} = Promotions.create(staff, branch.id, attrs)
    assert Repo.get!(Delivest.Promo.Promotion, promotion.id).crm_certificate == snapshot

    assert {:ok, retained} = Promotions.update(staff, promotion, %{"name" => "Новое имя"})
    assert retained.crm_certificate == snapshot

    assert {:ok, removed} =
             Promotions.update(staff, retained, %{"crm_certificate_token" => ""})

    assert removed.crm_certificate == nil

    info = Repo.get_by!(BranchInfo, branch_id: branch.id)
    info |> Ecto.Changeset.change(crm: %{generation: 1}) |> Repo.update!()
    assert {:error, :invalid_certificate_binding} = Certificates.binding(branch.id, token)
  end
end
