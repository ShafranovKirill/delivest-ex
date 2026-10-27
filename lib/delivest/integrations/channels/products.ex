defmodule Delivest.Integrations.Channels.Products do
  import Ecto.Query

  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.Channels.ChannelProduct

  def by_product(channel) do
    from(c in ChannelProduct, where: c.channel == ^to_string(channel))
    |> Repo.all()
    |> Map.new(&{&1.product_id, &1})
  end

  def get(channel, product_id),
    do: Repo.get_by(ChannelProduct, channel: to_string(channel), product_id: product_id)

  def enabled?(nil), do: true
  def enabled?(%ChannelProduct{enabled: enabled}), do: enabled

  def last_change(channel, product_ids) do
    from(c in ChannelProduct,
      where: c.channel == ^to_string(channel) and c.product_id in ^product_ids,
      select: max(c.updated_at)
    )
    |> Repo.one()
  end

  def update(staff, channel, product_id, attrs) do
    if Identity.can?(staff, "products.update") do
      (get(channel, product_id) ||
         %ChannelProduct{channel: to_string(channel), product_id: product_id})
      |> ChannelProduct.changeset(attrs)
      |> Repo.insert_or_update()
    else
      {:error, :forbidden}
    end
  end
end
