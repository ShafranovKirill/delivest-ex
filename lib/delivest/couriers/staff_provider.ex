defmodule Delivest.Couriers.StaffProvider do
  @behaviour Delivest.Couriers.Provider

  use Gettext, backend: DelivestWeb.Gettext

  @impl true
  def key, do: :staff

  @impl true
  def name, do: gettext("Own couriers")

  @impl true
  def start(_delivery, _order), do: {:ok, %{}}

  @impl true
  def cancel(_delivery), do: :ok
end
