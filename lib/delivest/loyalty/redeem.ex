defmodule Delivest.Loyalty.Redeem do
  alias Delivest.{Loyalty, Money}
  alias Delivest.Promo.Result

  def plan(%Result{} = result, attrs, client_id, branch_id) do
    case requested(attrs["spend_points"]) do
      0 -> {:ok, result}
      stars -> validate(result, stars, client_id, branch_id)
    end
  end

  def reapply(%Result{} = result, stars) when is_integer(stars) and stars > 0,
    do: {:ok, reduce(result, min(stars * 100, result.total))}

  def reapply(%Result{} = result, _stars), do: {:ok, result}

  def max_stars(%Result{} = result, settings, balance) do
    cap = div(result.total * (settings.max_percent || 50), 100)
    min(div(cap, 100), balance)
  end

  defp validate(result, stars, client_id, branch_id) do
    settings = Loyalty.settings(branch_id)

    cond do
      is_nil(client_id) or not Loyalty.enabled?(branch_id) or settings.spend_enabled != true ->
        {:error, :points_unavailable}

      stars > Loyalty.balance(client_id) ->
        {:error, :insufficient_points}

      stars > max_stars(result, settings, stars) ->
        {:error, :points_over_limit}

      true ->
        {:ok, reduce(result, stars * 100)}
    end
  end

  defp reduce(%Result{} = result, 0), do: result

  defp reduce(%Result{lines: lines} = result, kopecks) do
    shares = Money.distribute(kopecks, Enum.map(lines, & &1.total))
    spent = Enum.sum(shares)

    lines =
      Enum.zip_with(lines, shares, fn line, share -> %{line | total: line.total - share} end)

    %{
      result
      | lines: lines,
        total: result.total - spent,
        discount: result.discount + spent,
        points: div(spent, 100)
    }
  end

  defp requested(value) when is_integer(value) and value > 0, do: value

  defp requested(value) when is_binary(value) do
    case Integer.parse(value) do
      {stars, ""} when stars > 0 -> stars
      _invalid -> 0
    end
  end

  defp requested(_value), do: 0
end
