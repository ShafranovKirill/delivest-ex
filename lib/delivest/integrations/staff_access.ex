defmodule Delivest.Integrations.StaffAccess do
  @moduledoc "Network-wide access to integration setup in the staff console."

  import Ecto.Query

  alias Delivest.Features.Gate
  alias Delivest.Integrations.Crm.Registry, as: CrmRegistry
  alias Delivest.Repo

  @providers ~w(yandex_ads vk_ads dadata yookassa yandex_eda yandex_delivery atol ycart frontpad iiko rkeeper)a

  def providers do
    (@providers ++ CrmRegistry.keys())
    |> Enum.uniq()
    |> Enum.map(&{&1, "integration_#{&1}"})
  end

  def keys, do: Enum.map(providers(), &elem(&1, 1))
  def permission?(key), do: key in keys()

  def snapshot do
    gates =
      Repo.all(
        from gate in Gate,
          where: gate.feature in ^keys() and gate.scope_key == "franchise",
          select: {gate.feature, gate.enabled}
      )
      |> Map.new()

    Map.new(providers(), fn {provider, key} -> {provider, Map.get(gates, key, true)} end)
  end

  # Phone verification is part of checkout authentication, not an optional add-on.
  def allowed?(:zvonok), do: true

  def allowed?(provider) do
    case Keyword.fetch(providers(), provider) do
      {:ok, key} -> allowed_key?(key)
      :error -> false
    end
  end

  def allowed_key?(key) do
    if permission?(key) do
      case Repo.get_by(Gate, feature: key, scope_key: "franchise") do
        %Gate{enabled: enabled} -> enabled
        nil -> true
      end
    else
      false
    end
  end
end
