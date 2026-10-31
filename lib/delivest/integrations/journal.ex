defmodule Delivest.Integrations.Journal do
  import Ecto.Query

  require Logger

  alias Delivest.Integrations.Journal.{Mask, Request}
  alias Delivest.Repo

  @context {__MODULE__, :context}
  @limit 50

  def context, do: Process.get(@context, %{})

  def put_context(attrs), do: Process.put(@context, Map.merge(context(), Map.new(attrs)))

  def reset_context, do: Process.delete(@context)

  def scope(attrs, fun) do
    previous = context()
    put_context(attrs)

    try do
      fun.()
    after
      Process.put(@context, previous)
    end
  end

  def record(attrs) do
    attrs = Map.merge(context(), Map.new(attrs))

    %Request{
      provider: attrs.provider |> to_string() |> String.slice(0, 64),
      branch_id: uuid(attrs[:branch_id]),
      order_id: uuid(attrs[:order_id]),
      direction: attrs.direction,
      method: attrs.method |> to_string() |> String.upcase(),
      url: attrs.url,
      status: attrs[:status],
      duration_ms: attrs[:duration_ms],
      request: Mask.body(attrs[:request]),
      response: Mask.body(attrs[:response]),
      error: attrs[:error]
    }
    |> Repo.insert()
  rescue
    error ->
      Logger.warning("integration journal: #{Exception.message(error)}")
      {:error, error}
  end

  def outgoing(provider, method, url, request, result, duration_ms) do
    {status, response, error} =
      case result do
        {:ok, %{status: status, body: body}} -> {status, body, nil}
        {:error, exception} -> {nil, nil, Exception.message(exception)}
      end

    record(%{
      provider: provider,
      direction: :out,
      method: method,
      url: Mask.url(url),
      status: status,
      duration_ms: duration_ms,
      request: request,
      response: response,
      error: error
    })
  end

  def list(provider, branch_id, opts \\ []) do
    Request
    |> where([r], r.provider == ^to_string(provider))
    |> by_branch(branch_id)
    |> failed(Keyword.get(opts, :failed, false))
    |> order_by([r], desc: r.id)
    |> limit(^Keyword.get(opts, :limit, @limit))
    |> Repo.all()
  end

  def for_order(order_id) do
    Request
    |> where([r], r.order_id == ^order_id)
    |> order_by([r], asc: r.id)
    |> Repo.all()
  end

  def prune(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)
    {count, _} = Request |> where([r], r.inserted_at < ^cutoff) |> Repo.delete_all()
    count
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp by_branch(query, nil), do: query
  defp by_branch(query, branch_id), do: where(query, [r], r.branch_id == ^branch_id)

  defp failed(query, false), do: query

  defp failed(query, true),
    do: where(query, [r], not is_nil(r.error) or r.status >= 400)
end
