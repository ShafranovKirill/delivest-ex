defmodule Delivest.Identity.ClientAuthStartTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Delivest.Identity.{ClientAuth, PhoneConfirmation}
  alias Delivest.Integrations.Health.Status
  alias Delivest.Integrations.Journal.Request
  alias Delivest.Integrations.Zvonok.Settings
  alias Delivest.Repo

  @phone "+79991239901"

  setup do
    Req.Test.set_req_test_to_private()
    :ok
  end

  defp with_unboxed_database(fun) do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      settings =
        Repo.insert!(%Settings{
          public_key: "test-key",
          campaign_id: "123",
          webhook_token: "test-webhook"
        })

      try do
        fun.()
      after
        Repo.delete_all(from c in PhoneConfirmation, where: like(c.phone, "+799912399%"))

        Repo.delete_all(
          from r in Request, where: r.provider == "zvonok" and like(r.url, "%799912399%")
        )

        Repo.delete_all(from s in Status, where: s.provider == "zvonok" and is_nil(s.branch_id))
        Repo.delete!(settings)
      end
    end)
  end

  defp provider_response(conn, call_id) do
    Req.Test.json(conn, %{
      "status" => "ok",
      "data" => %{"call_id" => call_id, "allowed_phones_for_call" => ["+78005553535"]}
    })
  end

  test "concurrent starts for the same normalized phone reuse one provider call" do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, {:provider_called, self()})

      receive do
        :release_provider -> :ok
      after
        5_000 -> flunk("provider barrier was not released")
      end

      provider_response(conn, "provider-1")
    end)

    with_unboxed_database(fn ->
      tasks =
        [@phone, "8 (999) 123-99-01", @phone, "8 (999) 123-99-01"]
        |> Enum.map(fn phone ->
          Task.async(fn ->
            :ok = Req.Test.allow(Delivest.HTTP.Client, test_pid, self())
            send(test_pid, :task_started)

            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
              ClientAuth.start(phone, "same-session")
            end)
          end)
        end)

      try do
        for _ <- 1..4, do: assert_receive(:task_started)
        assert_receive {:provider_called, provider_pid}
        send(provider_pid, :release_provider)
        results = Enum.map(tasks, &Task.await(&1, 30_000))

        assert Enum.all?(results, &match?({:ok, _, "+78005553535"}, &1))

        assert results
               |> Enum.map(fn {:ok, confirmation, _} -> confirmation.id end)
               |> Enum.uniq()
               |> length() == 1

        refute_receive {:provider_called, _}

        assert Repo.aggregate(from(c in PhoneConfirmation, where: c.phone == ^@phone), :count) ==
                 1
      after
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
      end
    end)
  end

  test "concurrent different phones share the session limit" do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, :provider_called)
      provider_response(conn, Ecto.UUID.generate())
    end)

    with_unboxed_database(fn ->
      results =
        2..5
        |> Task.async_stream(
          fn suffix ->
            phone = "+7999123990#{suffix}"
            :ok = Req.Test.allow(Delivest.HTTP.Client, test_pid, self())

            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
              ClientAuth.start(phone, "one-session")
            end)
          end,
          max_concurrency: 4,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, _, _}, &1)) == 3
      assert Enum.count(results, &match?({:error, {:rate_limited, _}}, &1)) == 1
      assert_receive :provider_called
      assert_receive :provider_called
      assert_receive :provider_called
      refute_receive :provider_called
    end)
  end

  test "provider failures consume the limit but cannot be reused or confirmed" do
    test_pid = self()

    Req.Test.stub(Delivest.HTTP.Client, fn conn ->
      send(test_pid, :provider_called)
      Req.Test.json(conn, %{"status" => "error", "error" => "unavailable"})
    end)

    with_unboxed_database(fn ->
      for session <- 1..3 do
        assert {:error, {:zvonok, _}} = ClientAuth.start(@phone, "session-#{session}")
      end

      assert {:error, {:rate_limited, _}} = ClientAuth.start(@phone, "session-4")
      assert_receive :provider_called
      assert_receive :provider_called
      assert_receive :provider_called
      refute_receive :provider_called

      reservations = Repo.all(from c in PhoneConfirmation, where: c.phone == ^@phone)
      assert length(reservations) == 3

      for reservation <- reservations do
        assert String.starts_with?(reservation.call_id, "pending:")
        assert reservation.call_number == nil
        assert {:error, :not_found} = ClientAuth.confirm_call(reservation.call_id, @phone)
      end
    end)
  end

  test "unexpected provider exception rolls back the reservation" do
    Req.Test.stub(Delivest.HTTP.Client, fn _conn -> raise "provider crashed" end)

    with_unboxed_database(fn ->
      assert_raise RuntimeError, "provider crashed", fn -> ClientAuth.start(@phone, "session") end
      assert Repo.aggregate(from(c in PhoneConfirmation, where: c.phone == ^@phone), :count) == 0
    end)
  end
end
