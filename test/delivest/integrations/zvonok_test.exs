defmodule Delivest.Integrations.ZvonokTest do
  use ExUnit.Case, async: false

  alias Delivest.Integrations.Zvonok
  alias Delivest.Integrations.Zvonok.Settings

  setup do
    previous = Application.get_env(:delivest, Delivest.HTTP.Client)
    on_exit(fn -> Application.put_env(:delivest, Delivest.HTTP.Client, previous) end)
    :ok
  end

  test "the confirmation call is not retried by the HTTP client" do
    Application.put_env(:delivest, Delivest.HTTP.Client,
      req_options: [plug: {Req.Test, Delivest.HTTP.Client}, retry: :safe_transient]
    )

    counter = :counters.new(1, [])

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      :counters.add(counter, 1, 1)
      conn |> Plug.Conn.send_resp(502, "bad gateway")
    end)

    settings = %Settings{public_key: "key", campaign_id: "campaign"}

    assert {:error, _reason} = Zvonok.Api.confirm(settings, "+79991234567")
    assert :counters.get(counter, 1) == 1
  end
end
