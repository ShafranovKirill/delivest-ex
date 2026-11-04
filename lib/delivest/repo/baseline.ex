defmodule Delivest.Repo.Baseline do
  @moduledoc false

  alias Ecto.Migration

  # Versions shipped through v1.2.6. Keep their rows on existing installations.
  @legacy_versions ~w(
  20260801000001 20260801000002 20260801000003 20260801000004 20260801000005
  20260801000006 20261021000001 20261022000001 20261023000001 20261024000001
  20261025000001 20261026000001 20261027000001 20261028000001 20261028141722
  20261029000001 20261029000002 20261029000003 20261030000001 20261031000001
  20261031052650 20261031060535 20261101000001 20261101000002 20261102000001
  20261102183731 20261102200722 20261102210926 20261102212717 20261103000001
  20261104000001 20261105000001 20261106000001 20261107000001 20261107000002
  20261107000003 20261108000001 20261109000001 20261109000002 20261110000001
  20261111000001 20261111000002 20261112000001 20261113000001 20261114000001
  20261115000001 20261116000001 20261116000002 20261116000003 20261116000004
  20261117000001 20261118000001 20261119000001 20261120000001 20261121000001
  20261121000002 20261122000001 20261122000002 20261123000001 20261123000002
  20261124000001 20261124000002 20261124000003 20261125000001 20261125000002
  20261130000001 20261130000002 20261130000003 20261201000001 20261201000002
  20261201000003 20261201000004 20261201000005 20261202000001 20261202000002
  20261203000001 20261203000002 20261203000003 20261204000001 20261204000002
  20261205000001 20261205000002 20261205000003 20261206000001 20261207000001
  20261208000001 20261209000002 20261210000001
  ) |> Enum.map(&String.to_integer/1)

  @baseline_tables ~w(
  app_logs audit_events branch_info branches cart_items
  carts categories channel_products client_addresses client_push_subscriptions
  clients courier_settlements crm_catalog_snapshots dadata_settings deliveries
  delivery_settings delivery_zones domain_events entity_relations external_ids
  fiscal_receipts franchise_ratings franchise_settings integration_health integration_inbox
  integration_requests legal_documents loyalty_accounts loyalty_entries loyalty_expiry_notifications
  media_files modifier_groups modifier_stops modifiers oban_jobs oban_peers
  order_counters order_item_modifiers order_items order_payments order_refunds
  order_transitions orders phone_confirmations product_modifier_groups product_stops
  product_tags products promo_codes promo_redemptions promotions
  push_keys push_subscriptions roles site_snapshot_installation site_snapshot_mappings
  staff staff_branches staff_push_subscriptions stocks yandex_delivery_journals
  yandex_eda_busy_modes yandex_eda_settings yookassa_settings zvonok_settings
  )

  def initialize(repo, schema) do
    versions = versions(repo)
    tables = tables(repo)

    if MapSet.size(versions) == 0 and MapSet.size(tables) == 0 do
      install(schema)
    else
      validate_existing!(versions, tables)
    end
  end

  def apply_schema(repo, schema) do
    unless MapSet.member?(versions(repo), 20_261_210_000_001), do: install(schema)
  end

  def irreversible!, do: raise("The Delivest baseline is irreversible")

  defp install(schema) do
    Migration.execute("SET LOCAL check_function_bodies = false")

    schema
    |> String.split("\n-- next statement\n")
    |> Enum.each(&Migration.execute/1)
  end

  defp versions(repo) do
    %{rows: rows} = repo.query!("SELECT version FROM public.schema_migrations")
    MapSet.new(rows, fn [version] -> version end)
  end

  defp tables(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT tablename FROM pg_catalog.pg_tables
      WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
      """)

    MapSet.new(rows, fn [table] -> table end)
  end

  defp validate_existing!(versions, tables) do
    missing_versions = Enum.reject(@legacy_versions, &MapSet.member?(versions, &1))
    missing_tables = Enum.reject(@baseline_tables, &MapSet.member?(tables, &1))

    if missing_versions != [] or missing_tables != [] do
      raise """
      Cannot adopt the Delivest baseline. Upgrade the database with v1.2.6 first.
      Missing migration versions: #{inspect(missing_versions)}
      Missing tables: #{inspect(missing_tables)}
      """
    end
  end
end
