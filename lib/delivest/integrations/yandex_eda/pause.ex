defmodule Delivest.Integrations.YandexEda.Pause do
  alias Delivest.Integrations.YandexEda.{Clock, PushApi}

  @tags ~w(too_busy technical_problem)
  @delivery_types ~w(ddc marketplace)

  def tags, do: @tags

  def start(settings, branch_id, minutes, tag) when tag in @tags do
    now = DateTime.utc_now()

    attrs =
      %{from: Clock.format(now), tag: tag}
      |> put_until(now, minutes)

    PushApi.block(settings, vendors(branch_id), attrs)
  end

  def start(_settings, _branch_id, _minutes, _tag), do: {:error, :invalid_tag}

  def stop(settings, branch_id, block_ids),
    do: PushApi.unblock(settings, vendors(branch_id), block_ids)

  def list(settings, branch_id) do
    with {:ok, items} <- PushApi.blocks(settings, vendors(branch_id)),
         do: {:ok, items |> Enum.map(&view/1) |> Enum.uniq_by(& &1.id)}
  end

  defp put_until(attrs, _now, nil), do: attrs

  defp put_until(attrs, now, minutes),
    do: Map.put(attrs, :to, now |> DateTime.add(minutes, :minute) |> Clock.format())

  defp vendors(branch_id),
    do: for(type <- @delivery_types, do: %{vendorId: branch_id, deliveryType: type})

  defp view(item) do
    %{
      id: item["blockId"],
      from: time(item["from"]),
      to: time(item["to"]),
      source: item["source"],
      message: item["message"],
      cancelable: item["availableToCancel"] != false
    }
  end

  defp time(value) do
    case Clock.parse(value) do
      {:ok, datetime} -> Clock.local(datetime)
      :error -> nil
    end
  end
end
