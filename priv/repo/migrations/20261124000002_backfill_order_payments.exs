defmodule Delivest.Repo.Migrations.BackfillOrderPayments do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO order_payments
      (id, order_id, branch_id, method, amount, status, provider, collected_by_id,
       paid_at, fiscalized_by, details, inserted_at, updated_at)
    SELECT gen_random_uuid(), o.id, o.branch_id,
      CASE o.payment_method WHEN 'cash' THEN 'cash' WHEN 'card_offline' THEN 'card' ELSE 'aggregator' END,
      o.total_amount, 'paid',
      CASE WHEN o.payment_method = 'online' THEN o.source END,
      t.staff_id,
      COALESCE(t.inserted_at, o.updated_at),
      CASE WHEN o.payment_method = 'online' THEN 'aggregator' END,
      '{}'::jsonb, now(), now()
    FROM orders o
    LEFT JOIN LATERAL (
      SELECT staff_id, inserted_at FROM order_transitions
      WHERE order_id = o.id AND "to" = 'completed' AND reverted_at IS NULL
      ORDER BY id DESC LIMIT 1
    ) t ON true
    WHERE o.status = 'completed' AND o.total_amount > 0
      AND NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.id)
    """

    execute """
    INSERT INTO order_payments
      (id, order_id, branch_id, method, amount, status, details, inserted_at, updated_at)
    SELECT gen_random_uuid(), o.id, o.branch_id,
      CASE o.payment_method WHEN 'cash' THEN 'cash' ELSE 'card' END,
      o.total_amount, 'pending', '{}'::jsonb, now(), now()
    FROM orders o
    WHERE o.status NOT IN ('completed', 'cancelled') AND o.deleted_at IS NULL
      AND o.payment_method IN ('cash', 'card_offline') AND o.total_amount > 0
      AND NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.id)
    """
  end

  def down, do: :ok
end
