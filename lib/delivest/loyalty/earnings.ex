defmodule Delivest.Loyalty.Earnings do
  alias Delivest.{Loyalty, Net}

  def price(result, branch_id) do
    if branch_id && Loyalty.enabled?(branch_id) do
      settings = Loyalty.settings(branch_id)
      products = Net.list_products_by_ids(Enum.map(result.lines, & &1.product_id))

      lines =
        Enum.map(result.lines, fn line ->
          reward =
            case products[line.product_id] do
              %{stars_reward: reward} when is_integer(reward) -> reward
              _ -> 0
            end

          %{line | stars_reward: if(line.gift or line.stars > 0, do: 0, else: reward)}
        end)

      base = div(max(result.total, 0), settings.per_rubles * 100) * settings.stars
      extra = Enum.sum(Enum.map(lines, &(&1.stars_reward * &1.quantity)))

      %{
        result
        | lines: lines,
          points_earned: base + extra,
          base_stars: base,
          product_stars: extra
      }
    else
      result
    end
  end
end
