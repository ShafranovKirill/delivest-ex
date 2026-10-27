defmodule Delivest.Delivery.Geometry do
  @min_points 3
  @max_points 499

  def normalize(%{"type" => "Polygon", "coordinates" => [ring | _holes]}),
    do: normalize_ring(ring)

  def normalize(_polygon), do: {:error, "is not a polygon"}

  defp normalize_ring(ring) when is_list(ring) do
    points =
      ring
      |> Enum.map(&point/1)
      |> drop_closing()

    cond do
      Enum.any?(points, &is_nil/1) -> {:error, "has broken points"}
      length(points) < @min_points -> {:error, "needs at least 3 points"}
      length(points) > @max_points -> {:error, "has too many points"}
      true -> {:ok, %{"type" => "Polygon", "coordinates" => [points ++ [hd(points)]]}}
    end
  end

  defp normalize_ring(_ring), do: {:error, "is not a polygon"}

  defp point([lng, lat | _rest])
       when is_number(lng) and is_number(lat) and lng >= -180 and lng <= 180 and lat >= -90 and
              lat <= 90,
       do: [round6(lng), round6(lat)]

  defp point(_point), do: nil

  defp round6(value), do: Float.round(value * 1.0, 6)

  defp drop_closing([first | _] = points) do
    if List.last(points) == first and length(points) > 1, do: Enum.drop(points, -1), else: points
  end

  defp drop_closing(points), do: points

  def ring(%{"coordinates" => [ring | _holes]}), do: ring

  def contains?(polygon, {lat, lng}) do
    polygon
    |> ring()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(false, fn [[x1, y1], [x2, y2]], inside ->
      if y1 > lat != y2 > lat and lng < (x2 - x1) * (lat - y1) / (y2 - y1) + x1,
        do: not inside,
        else: inside
    end)
  end
end
