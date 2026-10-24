defmodule DelivestWeb.Client.Promotion.PromotionJSON do
  def index(%{promotions: promotions}),
    do: %{data: Enum.map(promotions, &Map.take(&1, [:id, :name, :description, :ends_at]))}
end
