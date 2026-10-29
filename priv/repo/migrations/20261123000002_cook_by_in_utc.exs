defmodule Delivest.Repo.Migrations.CookByInUtc do
  use Ecto.Migration

  def up do
    execute """
    UPDATE orders o SET cook_by = timezone('UTC', timezone(COALESCE(i.timezone, f.timezone, 'Europe/Moscow'), o.cook_by))
    FROM orders src
    LEFT JOIN branch_info i ON i.branch_id = src.branch_id
    LEFT JOIN LATERAL (SELECT timezone FROM franchise_settings LIMIT 1) f ON true
    WHERE o.id = src.id AND o.cook_by IS NOT NULL
    """
  end

  def down do
    execute """
    UPDATE orders o SET cook_by = timezone(COALESCE(i.timezone, f.timezone, 'Europe/Moscow'), timezone('UTC', o.cook_by))
    FROM orders src
    LEFT JOIN branch_info i ON i.branch_id = src.branch_id
    LEFT JOIN LATERAL (SELECT timezone FROM franchise_settings LIMIT 1) f ON true
    WHERE o.id = src.id AND o.cook_by IS NOT NULL
    """
  end
end
