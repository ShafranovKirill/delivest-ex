defmodule Delivest.Oms.OrderScopes do
  import Ecto.Query

  def cancelled do
    dynamic(
      [o],
      o.status == :cancelled or
        fragment("coalesce(?->>'remote_status', '') = 'cancelled'", o.channel) or
        (o.status == :crm and
           fragment("coalesce(?->>'remote_status', '') = 'cancelled'", o.crm))
    )
  end

  def lost do
    dynamic(
      [o],
      o.status == :crm and fragment("coalesce(?->>'status', '') = 'failed'", o.crm)
    )
  end

  def sold, do: dynamic(not (^cancelled()) and not (^lost()))

  def sold(query), do: where(query, ^sold())

  def effective_status do
    dynamic(
      [o],
      fragment(
        "CASE WHEN ? = 'crm' THEN coalesce(?->>'remote_status', 'created') ELSE ? END",
        o.status,
        o.crm,
        o.status
      )
    )
  end
end
