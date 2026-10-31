defmodule Delivest.Integrations.RkeeperContractTest do
  use Delivest.DataCase, async: false

  alias Delivest.Integrations.Rkeeper

  @moduletag :contract
  @moduletag :rkeeper_contract

  setup do
    http = Application.get_env(:delivest, Delivest.HTTP.Client)
    rkeeper = Application.get_env(:delivest, Rkeeper, [])
    Application.put_env(:delivest, Delivest.HTTP.Client, req_options: [retry: false])
    Application.put_env(:delivest, Rkeeper, token: System.fetch_env!("RKEEPER_TOKEN"))

    on_exit(fn ->
      Application.put_env(:delivest, Delivest.HTTP.Client, http)
      Application.put_env(:delivest, Rkeeper, rkeeper)
    end)

    %{settings: %Rkeeper.Settings{object_id: "199990377", sandbox: true}}
  end

  test "the test restaurant answers", %{settings: settings} do
    IO.puts("rkeeper available: #{inspect(Rkeeper.available(settings))}")
    IO.puts("rkeeper void reasons: #{inspect(Rkeeper.dictionaries(settings))}")
    assert {:ok, dishes} = Rkeeper.fetch_catalog(settings)
    IO.puts("rkeeper dishes: #{length(dishes)}")
    assert {:ok, stops} = Rkeeper.fetch_stops(settings)
    IO.puts("rkeeper stops: #{inspect(stops)}")
  end
end
