defmodule Delivest.Repo.Migrations.EnforceStorefrontEpochSingleton do
  use Ecto.Migration

  def up do
    execute("CREATE UNIQUE INDEX storefront_epoch_singleton ON storefront_epoch ((true))")
  end

  def down do
    execute("DROP INDEX storefront_epoch_singleton")
  end
end
