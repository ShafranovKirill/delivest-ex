defmodule Delivest.Oms.OrderScopes do
  import Ecto.Query

  def cancelled, do: dynamic([o], o.status == :cancelled)

  def lost do
    dynamic(
      [o],
      o.status == :created and fragment("coalesce(?->>'status', '') = 'failed'", o.crm)
    )
  end

  def sold, do: dynamic(not (^cancelled()) and not (^lost()))

  def sold(query), do: where(query, ^sold())
end
