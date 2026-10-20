defmodule Delivest.Promo.Dsl.Syntax do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Promo.Dsl.Error

  def parse(text) when is_binary(text) do
    with {:ok, tokens} <- tokenize(text) do
      tokens |> :promo_parser.parse() |> parsed()
    end
  end

  defp tokenize(text) do
    case text |> String.to_charlist() |> :promo_lexer.string({1, 1}) do
      {:ok, [], _end} ->
        {:error, [Error.at(nil, gettext("Rules are empty"))]}

      {:ok, tokens, _end} ->
        {:ok, tokens}

      {:error, {location, :promo_lexer, reason}, _end} ->
        {:error, [lexer_error(location, reason)]}
    end
  end

  defp parsed({:ok, ast}), do: {:ok, ast}

  defp parsed({:error, {location, :promo_parser, [_message, []]}}),
    do: {:error, [Error.at(location, gettext("Unexpected end of rules"))]}

  defp parsed({:error, {location, :promo_parser, [_message, token]}}) do
    message = gettext("Unexpected «%{token}»", token: unquote_token(token))
    {:error, [Error.at(location, message)]}
  end

  defp lexer_error(location, {:illegal, chars}),
    do: Error.at(location, gettext("Unknown symbol «%{symbol}»", symbol: List.to_string(chars)))

  defp lexer_error(location, _reason), do: Error.at(location, gettext("Invalid rules"))

  defp unquote_token(token), do: token |> List.to_string() |> String.trim("'")
end
