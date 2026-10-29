defmodule Delivest.Integrations.TokenCacheTest do
  use ExUnit.Case, async: true

  alias Delivest.Integrations.TokenCache

  setup do
    %{key: {:test, make_ref()}}
  end

  defp issuer(tokens) do
    counter = :counters.new(1, [])

    issue = fn ->
      :counters.add(counter, 1, 1)
      {:ok, Enum.at(tokens, :counters.get(counter, 1) - 1), 3600}
    end

    {issue, fn -> :counters.get(counter, 1) end}
  end

  test "a token is issued once and then taken from the cache", %{key: key} do
    {issue, issued} = issuer(["a", "b"])

    assert TokenCache.fetch(key, issue) == {:ok, "a"}
    assert TokenCache.fetch(key, issue) == {:ok, "a"}
    assert issued.() == 1
  end

  test "an issue error is returned and nothing is cached", %{key: key} do
    assert TokenCache.fetch(key, fn -> {:error, :invalid_client} end) == {:error, :invalid_client}
    assert TokenCache.fetch(key, fn -> {:ok, "a", 60} end) == {:ok, "a"}
  end

  test "an expired token is refreshed and the request repeated once", %{key: key} do
    {issue, issued} = issuer(["old", "new"])

    request = fn
      "old" -> {:error, {:http_error, 401, %{}}}
      "new" -> {:ok, :done}
    end

    assert TokenCache.run(key, issue, request) == {:ok, :done}
    assert TokenCache.fetch(key, issue) == {:ok, "new"}
    assert issued.() == 2
  end

  test "a second auth error is returned as is", %{key: key} do
    {issue, issued} = issuer(["a", "b"])
    error = {:error, {:http_error, 401, %{}}}

    assert TokenCache.run(key, issue, fn _token -> error end) == error
    assert issued.() == 2
  end

  test "the provider decides what an expired token looks like", %{key: key} do
    {issue, issued} = issuer(["a", "b"])
    expired? = &match?({:error, :token_expired}, &1)

    request = fn
      "a" -> {:error, :token_expired}
      "b" -> :ok
    end

    assert TokenCache.run(key, issue, request, expired?) == :ok
    assert issued.() == 2
  end

  test "invalidate drops the token", %{key: key} do
    {issue, issued} = issuer(["a", "b"])
    TokenCache.fetch(key, issue)
    TokenCache.invalidate(key)
    assert TokenCache.fetch(key, issue) == {:ok, "b"}
    assert issued.() == 2
  end
end
