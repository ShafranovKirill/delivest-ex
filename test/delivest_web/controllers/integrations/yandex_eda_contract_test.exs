defmodule DelivestWeb.Integrations.YandexEdaContractTest do
  use Delivest.DataCase, async: false

  import Delivest.YandexEdaFixtures

  alias Delivest.YandexEdaContract.{Collection, Newman}

  @moduletag :yandex_contract
  @moduletag :tmp_dir
  @moduletag timeout: :timer.minutes(3)

  setup do
    server = start_supervised!({Bandit, plug: DelivestWeb.Endpoint, ip: :loopback, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    branch = yandex_branch()

    %{
      host: "http://127.0.0.1:#{port}/integrations/yandex-eda",
      settings: credentials(),
      branch: branch,
      product: menu_product(branch, menu_category(branch), name: "Борщ", price: 300)
    }
  end

  test "the yandex eda partner collection passes", context do
    case Newman.run(Collection.prepare(context), context.tmp_dir) do
      {:ok, failures, output} -> assert failures == [], output
      {:error, output} -> flunk("newman did not run:\n" <> output)
    end
  end
end
