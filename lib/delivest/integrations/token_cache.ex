defmodule Delivest.Integrations.TokenCache do
  @cache :token_cache
  @max_margin 300

  @type key :: {provider :: atom(), account :: term()}
  @type issue :: (-> {:ok, String.t(), ttl_seconds :: pos_integer()} | {:error, term()})

  @spec fetch(key(), issue()) :: {:ok, String.t()} | {:error, term()}
  def fetch(key, issue) do
    fallback = fn ->
      case issue.() do
        {:ok, token, ttl} -> {:commit, token, expire: :timer.seconds(ttl - margin(ttl))}
        {:error, _reason} = error -> {:ignore, error}
      end
    end

    case Cachex.fetch(@cache, key, fallback) do
      {:ok, token} -> {:ok, token}
      {:commit, token} -> {:ok, token}
      {:ignore, error} -> error
    end
  end

  @spec run(key(), issue(), (String.t() -> result), (result -> boolean())) :: result
        when result: term()
  def run(key, issue, fun, expired? \\ &auth_error?/1) do
    with {:ok, token} <- fetch(key, issue) do
      result = fun.(token)

      if expired?.(result) do
        with {:ok, token} <- refresh(key, issue), do: fun.(token)
      else
        result
      end
    end
  end

  def invalidate(key), do: Cachex.del(@cache, key)

  def auth_error?({:error, {:http_error, 401, _body}}), do: true
  def auth_error?(_result), do: false

  defp refresh(key, issue) do
    invalidate(key)
    fetch(key, issue)
  end

  defp margin(ttl) when ttl > 1, do: min(div(ttl, 10), @max_margin)
  defp margin(_ttl), do: 0
end
