defmodule Delivest.Repo.Migrations.MoveBranchCoordinatesToInfo do
  use Ecto.Migration

  def up do
    alter table(:branch_info) do
      add :latitude, :float
      add :longitude, :float
    end

    flush()

    execute """
    UPDATE branch_info
    SET latitude = (ycart_settings->>'latitude')::float,
        longitude = (ycart_settings->>'longitude')::float,
        address = COALESCE(NULLIF(address, ''), ycart_settings->>'address'),
        ycart_settings = ycart_settings - 'latitude' - 'longitude' - 'address'
    WHERE ycart_settings IS NOT NULL
    """
  end

  def down do
    execute """
    UPDATE branch_info
    SET ycart_settings = COALESCE(ycart_settings, '{}'::jsonb) ||
      jsonb_build_object('latitude', latitude, 'longitude', longitude, 'address', address)
    """

    alter table(:branch_info) do
      remove :latitude
      remove :longitude
    end
  end
end
