defmodule Delivest.Integrations.StaffAccess do
  @moduledoc "Network-wide access to integration setup in the staff console."

  alias Delivest.Features.Gate
  alias Delivest.Repo

  @providers ~w(yandex_ads vk_ads dadata yookassa yandex_eda yandex_delivery atol ycart frontpad iiko rkeeper)a
  @entries Enum.map(@providers, &{&1, "integration_#{&1}"})
  @keys Enum.map(@entries, &elem(&1, 1))

  def providers, do: @entries
  def keys, do: @keys
  def permission?(key), do: key in @keys

  # Phone verification is part of checkout authentication, not an optional add-on.
  def allowed?(:zvonok), do: true

  def allowed?(provider) do
    case Keyword.fetch(@entries, provider) do
      {:ok, key} -> allowed_key?(key)
      :error -> false
    end
  end

  def allowed_key?(key) when key in @keys do
    case Repo.get_by(Gate, feature: key, scope_key: "franchise") do
      %Gate{enabled: enabled} -> enabled
      nil -> true
    end
  end
end
