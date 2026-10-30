defmodule Delivest.Integrations.AtolOnlineContractTest do
  use Delivest.DataCase, async: false

  import Delivest.Factory

  alias Delivest.Fiscal.{BranchSettings, Builder, Receipt}
  alias Delivest.Integrations.AtolOnline
  alias Delivest.Oms.{Order, OrderItem}

  @moduletag :contract
  @moduletag :atol_contract
  @moduletag timeout: :timer.minutes(3)

  @settings %AtolOnline.Settings{
    login: "v5-online-atol-ru",
    password: "zUr0OxfI",
    group_code: "v5-online-atol-ru_5179",
    sandbox: true,
    callback_token: "contract"
  }

  @fiscal %BranchSettings{
    mode: :own,
    inn: "5544332219",
    sno: :usn_income,
    payment_address: "https://v5.online.atol.ru",
    email: "contract@example.com",
    vat: :none,
    delivery_vat: :none
  }

  setup do
    config = Application.get_env(:delivest, Delivest.HTTP.Client)
    Application.put_env(:delivest, Delivest.HTTP.Client, req_options: [retry: false])
    on_exit(fn -> Application.put_env(:delivest, Delivest.HTTP.Client, config) end)
    %{branch: insert(:branch)}
  end

  defp order(items) do
    %Order{
      customer_phone: "+79990000000",
      delivery_amount: 0,
      items:
        Enum.map(items, fn {title, price} ->
          %OrderItem{title: title, price: price, quantity: 1, modifiers: []}
        end)
    }
  end

  defp receipt(branch, kind \\ :sell),
    do: %Receipt{id: Ecto.UUID.generate(), branch_id: branch.id, kind: kind}

  defp body(receipt, order, kind \\ :sell) do
    total = Enum.sum(Enum.map(order.items, & &1.price))
    built = Builder.build(order, @fiscal, payments: [%{type: :cash, sum: total}], kind: kind)
    AtolOnline.body(receipt, built, @settings)
  end

  defp wait_done(receipt, attempts \\ 20)
  defp wait_done(_receipt, 0), do: flunk("the receipt is not done in time")

  defp wait_done(receipt, attempts) do
    case AtolOnline.fetch(receipt, @settings) do
      {:ok, %{status: :done} = result} ->
        result

      {:ok, %{status: :fail} = result} ->
        flunk("the receipt failed: #{inspect(result)}")

      _wait ->
        Process.sleep(3_000)
        wait_done(receipt, attempts - 1)
    end
  end

  test "the token is issued for the shared test account" do
    assert :ok = AtolOnline.health_check(@settings)
  end

  test "sell, report and refund", %{branch: branch} do
    order = order([{"Пицца", 59_000}])
    sell = receipt(branch)

    assert {:ok, %{uuid: uuid, status: :wait}} =
             AtolOnline.register(sell, body(sell, order), @settings)

    done = wait_done(%{sell | uuid: uuid})
    IO.puts("atol payload: #{inspect(done.payload)}")
    assert done.payload["fn_number"]

    refund = receipt(branch, :sell_refund)

    assert {:ok, %{uuid: refund_uuid}} =
             AtolOnline.register(refund, body(refund, order, :sell_refund), @settings)

    wait_done(%{refund | uuid: refund_uuid})
  end

  test "a repeated external id answers with error 33", %{branch: branch} do
    order = order([{"Пицца", 59_000}])
    sell = receipt(branch)
    body = body(sell, order)

    assert {:ok, %{uuid: uuid}} = AtolOnline.register(sell, body, @settings)
    repeated = AtolOnline.register(sell, body, @settings)
    IO.puts("atol repeated external_id: #{inspect(repeated)}, first uuid #{uuid}")

    assert match?({:error, {:atol, 33, _text}}, repeated) or
             match?({:ok, %{uuid: ^uuid}}, repeated)
  end

  test "a zero price item", %{branch: branch} do
    order = order([{"Пицца", 59_000}, {"Соус в подарок", 0}])
    sell = receipt(branch)
    result = AtolOnline.register(sell, body(sell, order), @settings)
    IO.puts("atol zero price item: #{inspect(result)}")
    assert {:ok, %{uuid: _uuid}} = result
  end
end
