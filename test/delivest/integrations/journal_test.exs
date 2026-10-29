defmodule Delivest.Integrations.JournalTest do
  use Delivest.DataCase, async: true

  alias Delivest.HTTP.Client
  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Journal.Request

  @branch_id Ecto.UUID.generate()
  @order_id Ecto.UUID.generate()

  test "an outgoing request is journaled with the scope and masked secrets" do
    Req.Test.stub(Client, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "down", "token" => "t"})
    end)

    Journal.scope([branch_id: @branch_id, order_id: @order_id], fn ->
      assert {:error, {:http_error, 500, _body}} =
               Client.post("/orders", %{secret: "s", total: 100},
                 base_url: "https://crm.test",
                 journal: :frontpad
               )
    end)

    assert [%Request{} = request] = Journal.list(:frontpad, @branch_id)
    assert request.direction == :out
    assert request.method == "POST"
    assert request.url == "https://crm.test/orders"
    assert request.status == 500
    assert request.order_id == @order_id
    assert is_integer(request.duration_ms)
    assert Jason.decode!(request.request) == %{"secret" => "***", "total" => 100}
    assert Jason.decode!(request.response) == %{"error" => "down", "token" => "***"}
    assert Request.failed?(request)
    assert Journal.context() == %{}
  end

  test "get params go to the url and connection errors are kept" do
    Req.Test.stub(Client, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, {:connection_error, _message}} =
             Client.get("/confirm", [public_key: "k", phone: "7999"],
               base_url: "https://zvonok.test",
               journal: :zvonok
             )

    assert [request] = Journal.list(:zvonok, nil)
    assert request.url == "https://zvonok.test/confirm?public_key=%2A%2A%2A&phone=7999"
    assert request.request == nil
    assert request.status == nil
    assert request.error == "connection refused"
  end

  test "requests without a journal provider are not recorded" do
    Req.Test.stub(Client, &Req.Test.json(&1, %{}))
    assert {:ok, _body} = Client.get("/", [], base_url: "https://any.test")
    assert Repo.aggregate(Request, :count) == 0
  end

  test "failed filter and pruning" do
    {:ok, ok} =
      Journal.record(%{provider: :iiko, direction: :out, method: :get, url: "/", status: 200})

    {:ok, _bad} =
      Journal.record(%{provider: :iiko, direction: :out, method: :get, url: "/", status: 401})

    assert [%{status: 401}] = Journal.list(:iiko, nil, failed: true)

    old = DateTime.add(DateTime.utc_now(), -10, :day)
    Repo.update_all(from(r in Request, where: r.id == ^ok.id), set: [inserted_at: old])

    assert Journal.prune(7) == 1
    assert [%{status: 401}] = Journal.list(:iiko, nil)
  end
end
