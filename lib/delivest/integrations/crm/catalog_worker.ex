defmodule Delivest.Integrations.Crm.CatalogWorker do
  use Oban.Worker, queue: :crm, max_attempts: 1

  alias Delivest.Integrations.Crm.Catalog

  @impl Oban.Worker
  def perform(_job), do: Catalog.check_all()
end
