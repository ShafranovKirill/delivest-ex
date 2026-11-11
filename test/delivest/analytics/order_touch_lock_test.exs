defmodule Delivest.Analytics.OrderTouchLockTest do
  use ExUnit.Case, async: false

  import Delivest.Factory

  alias Delivest.{Features, Repo}
  alias Delivest.Advertising.{Attribution, Click, FirstSource, GuestClaim, Link, OrderAttribution}
  alias Delivest.Funnel.OrderReceipt
  alias Delivest.Oms.{Carts, Orders}
  alias DelivestWeb.AnalyticsIdentity
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    fixture =
      unboxed(fn ->
        preexisting_franchise_gates =
          Repo.query!(
            "SELECT feature, enabled FROM feature_gates WHERE scope_key='franchise' AND feature IN ('analytics_links', 'analytics_funnel', 'analytics_extended')"
          ).rows
          |> Map.new(fn [feature, enabled] -> {feature, enabled} end)

        branch = insert(:branch, is_active: true)
        client = insert(:client)

        for feature <- ["analytics_links", "analytics_funnel", "analytics_extended"] do
          {:ok, _} = Features.configure(feature, :franchise, true, actor: "lock-test")
          {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "lock-test")
        end

        product = insert_branch_product(branch.id, price: 300)
        {:ok, cart} = Carts.create_cart(%{session_id: Ecto.UUID.generate(), branch_id: branch.id})
        {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

        link =
          Repo.insert!(%Link{
            branch_id: branch.id,
            token: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false),
            campaign: "lock-test",
            name: "Lock test"
          })

        %{
          branch: branch,
          client: client,
          product: product,
          cart: cart,
          link: link,
          preexisting_franchise_gates: preexisting_franchise_gates
        }
      end)

    on_exit(fn -> unboxed(fn -> cleanup(fixture) end) end)
    fixture
  end

  test "checkout and actual source claim complete without inverted locks", fixture do
    guest = Ecto.UUID.generate()

    signed_conn =
      Plug.Test.conn(:get, "/")
      |> AnalyticsIdentity.put_guest_cookie(guest)
      |> Plug.Conn.fetch_cookies()

    assert {:ok, ^guest} = AnalyticsIdentity.guest_id(signed_conn)

    unboxed(fn ->
      Repo.insert!(%Click{
        link_id: fixture.link.id,
        branch_id: fixture.branch.id,
        guest_id: guest,
        clicked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })
    end)

    supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.RaceTasks})
    parent = self()
    handler = "claim-advisory-barrier-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:delivest, :repo, :query],
        fn _, _, metadata, _ ->
          if Process.get(:pause_claim_after_locks) &&
               String.contains?(metadata.query, "pg_advisory_xact_lock") do
            count = Process.get(:claim_locks_seen, 0) + 1
            Process.put(:claim_locks_seen, count)

            if count == 2 do
              send(parent, :claim_has_both_advisory_locks)

              receive do
                :resume_claim -> :ok
              end
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    claim =
      Task.Supervisor.async_nolink(supervisor, fn ->
        unboxed(fn ->
          Process.put(:pause_claim_after_locks, true)
          Attribution.claim(fixture.client.id, guest)
        end)
      end)

    assert_receive :claim_has_both_advisory_locks, 5_000

    attrs = Map.put(attrs(fixture), "customer_phone", fixture.client.phone)

    checkout =
      Task.Supervisor.async_nolink(supervisor, fn ->
        unboxed(fn ->
          Repo.transaction(fn ->
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:checkout_backend, backend_pid})

            Orders.create_order(attrs,
              authenticated_client_id: fixture.client.id,
              analytics_guest_id: guest,
              update_client: false
            )
          end)
        end)
      end)

    assert_receive {:checkout_backend, backend_pid}, 5_000
    assert advisory_wait?(backend_pid, 200)
    send(claim.pid, :resume_claim)

    assert {:ok, %{claimed: 1}} = Task.await(claim, 10_000)
    assert {:ok, {:ok, order}} = Task.await(checkout, 10_000)

    unboxed(fn ->
      assert Repo.get!(GuestClaim, guest).client_id == fixture.client.id
      assert Repo.get!(FirstSource, fixture.client.id).link_id == fixture.link.id
      assert Repo.get!(OrderAttribution, order.id).link_id == fixture.link.id
      assert Repo.get(OrderReceipt, order.id) == nil

      assert Repo.query!(
               "SELECT verified_client_id FROM analytics_order_identities WHERE order_id=$1",
               [Ecto.UUID.dump!(order.id)]
             ).rows == [[Ecto.UUID.dump!(fixture.client.id)]]

      assert Repo.query!("SELECT count(*) FROM orders WHERE id=$1", [Ecto.UUID.dump!(order.id)]).rows ==
               [[1]]
    end)
  end

  test "deferred insert and later correction dirty an unlinked funnel order", fixture do
    assert {:ok, order} = unboxed(fn -> Orders.create_order(attrs(fixture)) end)

    unboxed(fn ->
      assert Repo.get(OrderReceipt, order.id) == nil

      [[revision]] =
        Repo.query!(
          "SELECT revision FROM analytics_report_states WHERE feature='analytics_funnel' AND branch_id=$1",
          [Ecto.UUID.dump!(fixture.branch.id)]
        ).rows

      assert revision >= 1
      Repo.update!(Ecto.Changeset.change(order, status: :completed))

      assert Repo.query!(
               "SELECT revision FROM analytics_report_states WHERE feature='analytics_funnel' AND branch_id=$1",
               [Ecto.UUID.dump!(fixture.branch.id)]
             ).rows == [[revision + 1]]
    end)
  end

  defp attrs(fixture) do
    %{
      "cart_id" => fixture.cart.id,
      "branch_id" => fixture.branch.id,
      "fulfillment_type" => "pickup",
      "payment_method" => "cash"
    }
  end

  defp advisory_wait?(_backend_pid, 0), do: false

  defp advisory_wait?(backend_pid, attempts) do
    blocked? =
      unboxed(fn ->
        Repo.query!(
          "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid=$1 AND wait_event_type='Lock' AND query LIKE '%pg_advisory_xact_lock%')",
          [backend_pid]
        ).rows == [[true]]
      end)

    if blocked? do
      true
    else
      receive do
      after
        25 -> advisory_wait?(backend_pid, attempts - 1)
      end
    end
  end

  defp cleanup(fixture) do
    branch_id = Ecto.UUID.dump!(fixture.branch.id)
    cart_id = Ecto.UUID.dump!(fixture.cart.id)
    client_id = Ecto.UUID.dump!(fixture.client.id)

    Repo.query!(
      "DELETE FROM advertising_order_receipts WHERE order_id IN (SELECT id FROM orders WHERE cart_id=$1)",
      [cart_id]
    )

    Repo.query!(
      "DELETE FROM funnel_order_receipts WHERE order_id IN (SELECT id FROM orders WHERE cart_id=$1)",
      [cart_id]
    )

    Repo.query!(
      "DELETE FROM analytics_order_identities WHERE order_id IN (SELECT id FROM orders WHERE cart_id=$1)",
      [cart_id]
    )

    Repo.query!("DELETE FROM client_first_sources WHERE client_id=$1", [client_id])
    Repo.query!("DELETE FROM advertising_guest_claims WHERE client_id=$1", [client_id])

    Repo.query!("DELETE FROM advertising_clicks WHERE link_id=$1", [
      Ecto.UUID.dump!(fixture.link.id)
    ])

    Repo.query!(
      "DELETE FROM oban_jobs WHERE args->>'event_id' IN (SELECT id::text FROM domain_events WHERE aggregate_id IN (SELECT id FROM orders WHERE cart_id=$1))",
      [cart_id]
    )

    Repo.query!(
      "DELETE FROM domain_events WHERE aggregate_id IN (SELECT id FROM orders WHERE cart_id=$1)",
      [cart_id]
    )

    Repo.query!(
      "DELETE FROM audit_events WHERE subject_id IN (SELECT id::text FROM orders WHERE cart_id=$1)",
      [cart_id]
    )

    Repo.query!("DELETE FROM orders WHERE cart_id=$1", [cart_id])
    Repo.query!("DELETE FROM carts WHERE id=$1", [cart_id])
    Repo.query!("DELETE FROM advertising_links WHERE id=$1", [Ecto.UUID.dump!(fixture.link.id)])
    Repo.query!("DELETE FROM analytics_report_states WHERE branch_id=$1", [branch_id])

    Repo.query!("DELETE FROM background_schedules WHERE scope_key=$1", [
      "branch:" <> fixture.branch.id
    ])

    Repo.query!(
      "DELETE FROM oban_jobs WHERE worker='Delivest.Background.Runner' AND args->>'scope_key'=$1 AND args->>'kind' IN ('analytics.funnel', 'analytics.links', 'analytics.extended')",
      ["branch:" <> fixture.branch.id]
    )

    Repo.query!(
      "DELETE FROM feature_audits WHERE actor IN ('lock-test', 'lock-test-cleanup') AND scope_key=$1",
      ["branch:" <> fixture.branch.id]
    )

    Repo.query!("DELETE FROM feature_gates WHERE scope_key=$1", ["branch:" <> fixture.branch.id])

    Repo.query!("DELETE FROM entity_relations WHERE from_id=$1 AND to_id=$2", [
      branch_id,
      Ecto.UUID.dump!(fixture.product.id)
    ])

    Repo.delete!(fixture.product)
    Repo.delete!(fixture.client)
    Repo.delete!(fixture.branch)

    for feature <- ["analytics_links", "analytics_funnel", "analytics_extended"] do
      previous = Map.get(fixture.preexisting_franchise_gates, feature, false)
      {:ok, _} = Features.configure(feature, :franchise, previous, actor: "lock-test-cleanup")

      unless Map.has_key?(fixture.preexisting_franchise_gates, feature) do
        Repo.query!("DELETE FROM feature_gates WHERE scope_key='franchise' AND feature=$1", [
          feature
        ])
      end
    end

    Repo.query!(
      "DELETE FROM feature_audits WHERE actor IN ('lock-test', 'lock-test-cleanup') AND scope_key='franchise' AND feature IN ('analytics_links', 'analytics_funnel', 'analytics_extended')"
    )
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
