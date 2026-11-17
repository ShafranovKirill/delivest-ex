defmodule Delivest.Integrations.Journal.Mask do
  @secrets ~w(secret password pass token authorization api_key apikey public_key private_key apilogin)
  @mask "***"
  @max_length 16_000

  def body(nil), do: nil
  def body(%_{}), do: "<structured body>"
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
      form?(body) -> mask_form(body)
      true -> "<#{byte_size(body)} bytes>"
    end
  end

  def body(_body), do: "<structured body>"

  def url(url) do
    case URI.parse(url) do
      %URI{query: query} = uri when is_binary(query) ->
        query =
          query
          |> URI.query_decoder()
          |> Enum.map(fn {key, value} -> {key, pair_value(key, value)} end)
          |> URI.encode_query()

        URI.to_string(%{uri | query: query, userinfo: nil, fragment: nil})

      uri ->
        URI.to_string(%{uri | userinfo: nil, fragment: nil})
    end
  rescue
    ArgumentError -> "<invalid URL>"
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
    key in ["ms", "code", "code_verifier", "cid", "clientid", "client_id", "yclid", "userid", "user_id"] or
      Enum.any?(@secrets, &String.contains?(key, &1))
  end

  defp value(%{} = map) when not is_struct(map),
    do:
      Map.new(map, fn {key, value} -> {key, if(secret?(key), do: @mask, else: value(value))} end)

  defp value(list) when is_list(list), do: Enum.map(list, &value/1)
  defp value(%_{}), do: "<structured body>"
  defp value(tuple) when is_tuple(tuple), do: "<multipart body>"
  defp value(value), do: value

  defp pair_value(key, item) do
    cond do
      secret?(key) -> @mask
      is_binary(item) or is_number(item) or is_atom(item) -> item
      true -> "<structured body>"
    end
  end

  defp form?(body) do
    not String.contains?(body, ["\r", "\n"]) and
      Regex.match?(~r/\A[^=&\s]+=[^\r\n]*(?:&[^=&\s]+=[^\r\n]*)*\z/u, body)
  end

  defp mask_form(body) do
    body
    |> URI.query_decoder()
    |> Enum.map(fn {key, item} -> {key, pair_value(key, item)} end)
    |> URI.encode_query()
    |> truncate()
  rescue
    ArgumentError -> "<#{byte_size(body)} bytes>"
  end

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
