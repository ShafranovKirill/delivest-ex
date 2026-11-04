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
        with {:ok, token} <- refresh(key, token, issue), do: fun.(token)
      else
        result
      end
    end
  end

  def invalidate(key), do: Cachex.del(@cache, key)

  def auth_error?({:error, {:http_error, 401, _body}}), do: true
  def auth_error?(_result), do: false

  # A 401 may arrive after another request has already replaced the token. The
  # check and the new issue happen under one lock for the key, so a late answer
  # for an outdated token reuses the newer one instead of removing it.
  defp refresh(key, rejected, issue) do
    case Cachex.transaction(@cache, [key], fn -> refresh_locked(key, rejected, issue) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh_locked(key, rejected, issue) do
    case Cachex.get(@cache, key) do
      {:ok, token} when is_binary(token) and token != rejected ->
        {:ok, token}

      _missing_or_rejected ->
        issue_token(key, issue)
    end
  end

  defp issue_token(key, issue) do
    case issue.() do
      {:ok, token, ttl} ->
        case Cachex.put(@cache, key, token, expire: :timer.seconds(ttl - margin(ttl))) do
          {:ok, true} -> {:ok, token}
          {:error, reason} -> {:error, reason}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp margin(ttl) when ttl > 1, do: min(div(ttl, 10), @max_margin)
  defp margin(_ttl), do: 0
end
