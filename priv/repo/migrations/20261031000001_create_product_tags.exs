defmodule Delivest.Repo.Migrations.CreateProductTags do
  use Ecto.Migration

  def up do
    create table(:product_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :icon, :string
      add :icon_key, :string
      add :order, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime)
    end

    execute """
    WITH created AS (
      INSERT INTO product_tags (id, name, icon, "order", inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'Хит', 'flame', 1, now(), now()),
        (gen_random_uuid(), 'Новинка', 'sparkles', 2, now(), now()),
        (gen_random_uuid(), 'Острое', 'pepper', 3, now(), now()),
        (gen_random_uuid(), 'Вегетарианское', 'leaf', 4, now(), now()),
        (gen_random_uuid(), 'Детям', 'mood-kid', 5, now(), now()),
        (gen_random_uuid(), 'Выгодно', 'discount', 6, now(), now())
      RETURNING id, icon
    ),
    legacy(code, icon) AS (
      VALUES ('hit', 'flame'), ('new', 'sparkles'), ('spicy', 'pepper'), ('vegetarian', 'leaf')
    )
    UPDATE products AS p
    SET tags = COALESCE(
      (
        SELECT array_agg(created.id::text)
        FROM unnest(p.tags) AS old(value)
        JOIN legacy ON legacy.code = old.value
        JOIN created ON created.icon = legacy.icon
      ),
      '{}'
    )
    WHERE p.tags <> '{}'
    """
  end

  def down do
    execute "UPDATE products SET tags = '{}'"
    drop table(:product_tags)
  end
end
