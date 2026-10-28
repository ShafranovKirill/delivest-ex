defmodule Delivest.Integrations.YandexEda.MenuReloadTest do
  use Delivest.DataCase, async: true
  use Oban.Testing, repo: Delivest.Repo

  import Delivest.Factory
  import Delivest.YandexEdaFixtures

  alias Delivest.Integrations.YandexEda
  alias Delivest.Integrations.YandexEda.{MenuReloadWorker, Settings}
  alias Delivest.Net.Stops

  defp stop(branch) do
    staff = insert(:staff, role: build(:role, permissions: ["stops.update"]))
    insert(:staff_branch, staff: staff, branch: branch)
    product = menu_product(branch, menu_category(branch))
    {:ok, _stop} = Stops.stop(staff, branch.id, product, :today)
  end

  test "a stop asks yandex to reload the stop list of the branch" do
    branch = yandex_branch()
    stop(branch)

    assert_enqueued(
      worker: MenuReloadWorker,
      args: %{"branch_id" => branch.id, "operation" => "menu_stop_list"}
    )
  end

  test "branches without the channel do not push" do
    branch = yandex_branch(enabled: false)
    stop(branch)

    refute_enqueued(worker: MenuReloadWorker)
  end

  test "a product change asks yandex to reload the menu of the branch" do
    branch = yandex_branch()
    product = menu_product(branch, menu_category(branch))
    staff = insert(:staff, role: build(:role, permissions: ["products.update"]))

    {:ok, _} = Delivest.Net.update_product(staff, product, %{"name" => "Новый борщ"})

    assert_enqueued(
      worker: MenuReloadWorker,
      args: %{"branch_id" => branch.id, "operation" => "menu"}
    )
  end

  test "a channel price change reloads the menu of every enabled branch" do
    first = yandex_branch()
    second = yandex_branch()
    off = yandex_branch(enabled: false)
    product = menu_product(first, menu_category(first))
    staff = insert(:staff, role: build(:role, permissions: ["products.update"]))

    {:ok, _} = YandexEda.update_product(staff, product.id, %{"price" => "500"})

    for branch <- [first, second],
        do: assert_enqueued(worker: MenuReloadWorker, args: %{"branch_id" => branch.id})

    refute_enqueued(worker: MenuReloadWorker, args: %{"branch_id" => off.id})
  end

  test "new branch settings reload the menu" do
    branch = yandex_branch()
    admin = insert(:staff, role: build(:role, permissions: ["integrations.update"]))
    insert(:staff_branch, staff: admin, branch: branch)

    assert {:ok, %{markup_percent: 20}} =
             YandexEda.update_branch_settings(admin, branch.id, %{"markup_percent" => "20"})

    assert_enqueued(
      worker: MenuReloadWorker,
      args: %{"branch_id" => branch.id, "operation" => "menu"}
    )
  end

  test "the worker posts the reload with a push token" do
    test_pid = self()
    client_id = "push-#{System.unique_integer([:positive])}"

    Repo.insert!(%Settings{
      client_id: "ours",
      client_secret: "secret",
      partner_name: "delivest",
      push_client_id: client_id,
      push_client_secret: "push-secret"
    })

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {conn.request_path, conn.req_headers, body})

      case conn.request_path do
        "/oauth2/token" -> Req.Test.json(conn, %{"access_token" => "push", "expires_in" => 3600})
        "/menu/import/initiation" -> Req.Test.json(conn, %{})
      end
    end)

    assert {:ok, _} =
             perform_job(MenuReloadWorker, %{"branch_id" => "b1", "operation" => "menu_stop_list"})

    assert_received {"/oauth2/token", _headers, form}
    assert URI.decode_query(form) == %{"client_id" => client_id, "client_secret" => "push-secret"}

    assert_received {"/menu/import/initiation", headers, json}
    assert {"authorization", "Bearer push"} in headers
    assert {"partner-name", "delivest"} in headers
    assert Jason.decode!(json) == %{"restaurantId" => "b1", "operationType" => "menu_stop_list"}

    assert {:ok, _} = perform_job(MenuReloadWorker, %{"branch_id" => "b1", "operation" => "menu"})
    refute_received {"/oauth2/token", _headers, _form}
  end

  test "without push access the worker does nothing" do
    assert :ok = perform_job(MenuReloadWorker, %{"branch_id" => "b1", "operation" => "menu"})
  end
end
