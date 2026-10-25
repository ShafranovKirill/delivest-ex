defmodule Delivest.Identity.PhoneConfirmations do
  import Ecto.Query

  alias Delivest.Identity.PhoneConfirmation
  alias Delivest.Repo

  @ttl_minutes 10

  @spec create(map()) :: {:ok, PhoneConfirmation.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %PhoneConfirmation{}
    |> PhoneConfirmation.changeset(attrs)
    |> Repo.insert()
  end

  @spec confirm(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def confirm(call_id, phone) do
    PhoneConfirmation
    |> fresh()
    |> where([c], c.call_id == ^call_id and c.phone == ^phone and is_nil(c.confirmed_at))
    |> select([c], c.id)
    |> Repo.update_all(set: [confirmed_at: now()])
    |> case do
      {0, _} -> {:error, :not_found}
      {_count, ids} -> {:ok, ids}
    end
  end

  @spec pending?(String.t(), String.t() | nil) :: boolean()
  def pending?(id, session_id) when is_binary(session_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.exists?(owned(id, session_id))
      :error -> false
    end
  end

  def pending?(_id, _session_id), do: false

  @spec confirmed?(String.t(), String.t() | nil) :: boolean()
  def confirmed?(id, session_id) when is_binary(session_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        id |> owned(session_id) |> where([c], not is_nil(c.confirmed_at)) |> Repo.exists?()

      :error ->
        false
    end
  end

  def confirmed?(_id, _session_id), do: false

  def topic(id), do: "phone_confirmation:#{id}"

  @spec consume(String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :pending | :not_found}
  def consume(id, session_id) when is_binary(session_id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      id |> owned(session_id) |> take_confirmed() |> result(id, session_id)
    else
      :error -> {:error, :not_found}
    end
  end

  def consume(_id, _session_id), do: {:error, :not_found}

  def ttl_minutes, do: @ttl_minutes

  defp take_confirmed(query) do
    query
    |> where([c], not is_nil(c.confirmed_at))
    |> select([c], c.phone)
    |> Repo.update_all(set: [consumed_at: now()])
  end

  defp result({1, [phone]}, _id, _session_id), do: {:ok, phone}

  defp result(_taken, id, session_id) do
    if Repo.exists?(owned(id, session_id)), do: {:error, :pending}, else: {:error, :not_found}
  end

  defp owned(id, session_id) do
    PhoneConfirmation
    |> fresh()
    |> where([c], c.id == ^id and c.session_id == ^session_id and is_nil(c.consumed_at))
  end

  defp fresh(query) do
    since = DateTime.add(now(), -@ttl_minutes, :minute)
    where(query, [c], c.inserted_at >= ^since)
  end

  defp now, do: DateTime.utc_now(:second)
end
