defmodule Delivest.Integrations.Journal.Mask do
  @secrets ~w(secret password token authorization api_key apikey public_key private_key apilogin)
  @mask "***"
  @max_length 16_000

  def body(nil), do: nil
  def body(body) when is_map(body), do: body |> value() |> encode()

  def body([{_key, _value} | _rest] = pairs),
    do:
      pairs
      |> Enum.map_join("&", fn {key, value} -> "#{key}=#{pair_value(key, value)}" end)
      |> truncate()

  def body(body) when is_list(body), do: body |> value() |> encode()

  def body(body) when is_binary(body) do
    cond do
      not String.valid?(body) -> "<#{byte_size(body)} bytes>"
      json?(body) -> body |> Jason.decode!() |> body()
      true -> truncate(body)
    end
  end

  def body(body), do: body |> inspect() |> truncate()

  def url(url) do
    case URI.parse(url) do
      %URI{query: query} = uri when is_binary(query) ->
        query =
          query
          |> URI.query_decoder()
          |> Enum.map(fn {key, value} -> {key, pair_value(key, value)} end)
          |> URI.encode_query()

        URI.to_string(%{uri | query: query})

      _uri ->
        url
    end
  end

  def path(path, path_params) do
    path_params
    |> Enum.filter(fn {key, _value} -> secret?(key) end)
    |> Enum.reduce(path, fn {_key, value}, path ->
      String.replace(path, to_string(value), @mask)
    end)
  end

  def secret?(key) do
    key = key |> to_string() |> String.downcase()
    Enum.any?(@secrets, &String.contains?(key, &1))
  end

  defp value(%{} = map) when not is_struct(map),
    do:
      Map.new(map, fn {key, value} -> {key, if(secret?(key), do: @mask, else: value(value))} end)

  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value(value), do: value

  defp pair_value(key, value), do: if(secret?(key), do: @mask, else: value)

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, json} -> truncate(json)
      {:error, _reason} -> value |> inspect() |> truncate()
    end
  end

  defp json?(body) do
    String.starts_with?(String.trim_leading(body), ["{", "["]) and
      match?({:ok, _decoded}, Jason.decode(body))
  end

  defp truncate(text), do: String.slice(text, 0, @max_length)
end
