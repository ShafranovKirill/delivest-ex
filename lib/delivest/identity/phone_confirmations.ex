defmodule Delivest.Identity.PhoneConfirmations do
  import Ecto.Query

  alias Delivest.Identity.PhoneConfirmation
  alias Delivest.Repo

  @ttl_minutes 10
  @max_attempts 3
  @limits [{600, 3}, {86_400, 10}]

  @spec create(map()) :: {:ok, PhoneConfirmation.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %PhoneConfirmation{}
    |> PhoneConfirmation.changeset(attrs)
    |> Repo.insert()
  end

  @spec reusable(String.t(), String.t() | nil) :: PhoneConfirmation.t() | nil
  def reusable(phone, session_id) when is_binary(session_id) do
    PhoneConfirmation
    |> fresh()
    |> where([c], c.phone == ^phone and c.session_id == ^session_id)
    |> where([c], is_nil(c.confirmed_at) and is_nil(c.consumed_at))
    |> where([c], not is_nil(c.call_number) or not is_nil(c.code))
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def reusable(_phone, _session_id), do: nil

  @spec throttle(String.t(), String.t() | nil) :: :ok | {:error, {:rate_limited, pos_integer()}}
  def throttle(phone, session_id) do
    keys =
      if is_binary(session_id), do: [phone: phone, session_id: session_id], else: [phone: phone]

    waits =
      for {field, value} <- keys,
          {seconds, max} <- @limits,
          wait = wait(field, value, seconds, max),
          do: wait

    if waits == [], do: :ok, else: {:error, {:rate_limited, Enum.max(waits)}}
  end

  defp wait(field, value, seconds, max) do
    since = DateTime.add(now(), -seconds, :second)

    times =
      PhoneConfirmation
      |> where([c], field(c, ^field) == ^value and c.inserted_at > ^since)
      |> order_by([c], desc: c.inserted_at)
      |> limit(^max)
      |> select([c], c.inserted_at)
      |> Repo.all()

    if length(times) >= max do
      oldest = List.last(times)
      max(DateTime.diff(DateTime.add(oldest, seconds, :second), now()), 1)
    end
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

  @spec verify_code(String.t(), String.t() | nil, String.t()) ::
          {:ok, String.t()}
          | {:error, :not_found | :attempts_exhausted | {:invalid_code, non_neg_integer()}}
  def verify_code(id, session_id, code) when is_binary(session_id) and is_binary(code) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %PhoneConfirmation{mode: :flash} = confirmation <-
           id |> owned(session_id) |> where([c], is_nil(c.confirmed_at)) |> Repo.one() do
      check_code(confirmation, String.trim(code))
    else
      _ -> {:error, :not_found}
    end
  end

  def verify_code(_id, _session_id, _code), do: {:error, :not_found}

  defp check_code(%PhoneConfirmation{attempts: attempts}, _code) when attempts >= @max_attempts,
    do: {:error, :attempts_exhausted}

  defp check_code(confirmation, code) do
    if Plug.Crypto.secure_compare(confirmation.code, code) do
      {_count, _} =
        PhoneConfirmation
        |> where([c], c.id == ^confirmation.id and is_nil(c.confirmed_at))
        |> Repo.update_all(set: [confirmed_at: now()])

      {:ok, confirmation.id}
    else
      {_count, _} =
        PhoneConfirmation
        |> where([c], c.id == ^confirmation.id)
        |> Repo.update_all(inc: [attempts: 1])

      {:error, {:invalid_code, @max_attempts - confirmation.attempts - 1}}
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

  @spec prune(pos_integer()) :: non_neg_integer()
  def prune(days) do
    before = DateTime.add(now(), -days, :day)
    {count, _} = Repo.delete_all(from(c in PhoneConfirmation, where: c.inserted_at < ^before))
    count
  end

  def ttl_minutes, do: @ttl_minutes

  defp take_confirmed(query) do
    query
    |> where([c], not is_nil(c.confirmed_at))
    |> select([c], c.phone)
    |> Repo.update_all(set: [consumed_at: now()])
  end

  defp result({1, [phone]}, _id, _session_id), do: {:ok, phone}

  defp result(_taken, id, session_id) do
    # A second tab or a resumed mobile page may finish the same login concurrently.
    # Only the owning session may retry, within a short fixed window.
    retry_since = DateTime.add(now(), -30, :second)

    retry =
      PhoneConfirmation
      |> fresh()
      |> where([c], c.id == ^id and c.session_id == ^session_id)
      |> where([c], not is_nil(c.confirmed_at) and c.consumed_at >= ^retry_since)
      |> select([c], c.phone)
      |> Repo.one()

    cond do
      retry -> {:ok, retry}
      Repo.exists?(owned(id, session_id)) -> {:error, :pending}
      true -> {:error, :not_found}
    end
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
