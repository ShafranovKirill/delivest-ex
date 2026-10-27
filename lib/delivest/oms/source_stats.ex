defmodule Delivest.Oms.SourceStats do
  import Ecto.Query

  alias Delivest.{LocalTime, Repo}
  alias Delivest.Oms.Order

  def today(branch_id) do
    since = LocalTime.start_of_day_utc(LocalTime.today())

    from(o in Order,
      where: o.branch_id == ^branch_id and o.inserted_at >= ^since and is_nil(o.deleted_at),
      group_by: o.source,
      select:
        {o.source,
         %{
           orders: count(o.id),
           failed: filter(count(o.id), fragment("?->>'status' = 'failed'", o.crm))
         }}
    )
    |> Repo.all()
    |> Map.new()
  end
end
