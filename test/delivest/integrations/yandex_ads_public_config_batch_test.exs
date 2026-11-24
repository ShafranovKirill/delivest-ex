defmodule Delivest.Integrations.YandexAdsPublicConfigBatchTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.Features
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.Settings

  @streams [:browser, :conversions, :ecommerce]

  test "disabled public configuration keeps one integration gate read for all streams" do
    branch = insert(:branch, is_active: true)
    {old, reference_queries} = measure(fn -> reference_config(branch.id) end)
    assert {^old, 4} = measure(fn -> YandexAds.public_config(branch.id) end)
    assert reference_queries > 4
  end

  test "enabled streams, privacy and selection preserve exact configuration and token" do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)

    for feature <- ~w(yandex_browser yandex_conversions yandex_ecommerce) do
      assert {:ok, _} =
               Features.configure(feature, :franchise, true,
                 actor: "test",
                 selected_integration_branches: true
               )

      assert {:ok, _} = Features.configure(feature, {:branch, branch.id}, true, actor: "test")
    end

    settings =
      Repo.insert!(%Settings{
        id: 1,
        enabled: true,
        privacy_approved: true,
        browser_enabled: true,
        conversions_enabled: true,
        ecommerce_enabled: true,
        branch_ids: [branch.id],
        counter_id: "12345678",
        metrika_token: "metrika",
        measurement_token: "measurement",
        generation: 7
      })

    assert_parity(branch.id)
    {old, old_queries} = measure(fn -> reference_config(branch.id) end)
    assert {^old, 4} = measure(fn -> YandexAds.public_config(branch.id) end)
    assert old.enabled and old.capture and old.ecommerce
    assert old_queries > 4
    assert_parity(other.id)

    for attrs <- [
          %{browser_enabled: false},
          %{conversions_enabled: false},
          %{ecommerce_enabled: false},
          %{privacy_approved: false},
          %{branch_ids: []}
        ] do
      changed = settings |> Ecto.Changeset.change(attrs) |> Repo.update!()
      assert_parity(branch.id)
      Repo.update!(Ecto.Changeset.change(changed, Map.take(settings, Map.keys(attrs))))
    end

    version = YandexAds.public_config(branch.id).feature_version

    assert {:ok, _} =
             Features.configure("yandex_browser", {:branch, branch.id}, false, actor: "test")

    assert_parity(branch.id)
    assert YandexAds.public_config(branch.id).feature_version != version

    assert {:ok, _} =
             Features.configure("yandex_browser", {:branch, branch.id}, true, actor: "test")

    assert_parity(branch.id)
    assert YandexAds.public_config(branch.id).feature_version != version
  end

  test "unreadable stream credential preserves capture decisions and version" do
    branch = insert(:branch, is_active: true)

    assert {:ok, _} =
             Features.configure("yandex_conversions", :franchise, true,
               actor: "test",
               selected_integration_branches: true
             )

    assert {:ok, _} =
             Features.configure("yandex_conversions", {:branch, branch.id}, true, actor: "test")

    Repo.insert!(%Settings{
      id: 1,
      enabled: true,
      privacy_approved: true,
      conversions_enabled: true,
      branch_ids: [branch.id],
      counter_id: "12345678",
      legacy_metrika_token: <<1, 2, 3>>
    })

    assert "metrika_token" in YandexAds.get_settings().credential_errors
    assert_parity(branch.id)
    refute YandexAds.public_config(branch.id).capture
  end

  defp assert_parity(branch_id),
    do: assert(YandexAds.public_config(branch_id) == reference_config(branch_id))

  defp reference_config(branch_id) do
    settings = YandexAds.get_settings()

    feature_version =
      {settings.generation, Enum.map(@streams, &YandexAds.feature_token(&1, branch_id))}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    browser = YandexAds.enabled?(settings, :browser, branch_id)

    capture =
      browser or YandexAds.enabled?(settings, :conversions, branch_id) or
        YandexAds.enabled?(settings, :ecommerce, branch_id)

    %{
      enabled: browser,
      counter_id: if(browser, do: settings.counter_id),
      generation: settings.generation,
      feature_version: feature_version,
      ecommerce: browser and YandexAds.enabled?(settings, :ecommerce, branch_id),
      capture: capture,
      collection_basis: if(capture, do: "admin_approved", else: "disabled"),
      webvisor: false
    }
  end

  defp measure(fun) do
    handler = "yandex-public-batch-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, owner ->
        if self() == owner and not String.contains?(metadata[:query] || "", "schema_migrations"),
          do: send(owner, :sql_query)
      end,
      self()
    )

    try do
      result = fun.()
      {result, collect_queries(0)}
    after
      :telemetry.detach(handler)
    end
  end

  defp collect_queries(count) do
    receive do
      :sql_query -> collect_queries(count + 1)
    after
      0 -> count
    end
  end
end
