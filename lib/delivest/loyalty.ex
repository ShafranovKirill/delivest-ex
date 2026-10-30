defmodule Delivest.Loyalty do
  import Ecto.Query

  alias Delivest.{Audit, Gateway, Identity, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.{BranchInfo, LoyaltySettings}
  alias Delivest.Loyalty.{Account, Entry}
  alias Delivest.Oms.Order

  @history_limit 100

  def settings(%Branch{info: %BranchInfo{loyalty: %LoyaltySettings{} = loyalty}}), do: loyalty

  def settings(%Branch{id: id}), do: settings(id)

  def settings(branch_id) when is_binary(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %Branch{info: %BranchInfo{loyalty: %LoyaltySettings{} = loyalty}}} -> loyalty
      _ -> %LoyaltySettings{}
    end
  end

  def enabled?(%Branch{} = branch),
    do: settings(branch).enabled and Gateway.own?(branch, :loyalty)

  def enabled?(branch_id) when is_binary(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, branch} -> enabled?(branch)
      _ -> false
    end
  end

  def balance(client_id) do
    Repo.one(from(a in Account, where: a.client_id == ^client_id, select: a.balance)) || 0
  end

  def history(client_id, limit \\ @history_limit) do
    Repo.all(
      from(e in Entry,
        where: e.client_id == ^client_id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit
      )
    )
  end

  def stars_for(%Order{} = order, %LoyaltySettings{} = settings) do
    base = max(order.total_amount - (order.delivery_amount || 0), 0)
    div(base, settings.per_rubles * 100) * settings.stars
  end

  def accrue(%Order{client_id: nil}), do: {:ok, nil}
  def accrue(%Order{channel: %{}}), do: {:ok, nil}
  def accrue(%Order{crm: %{}}), do: {:ok, nil}

  def accrue(%Order{} = order) do
    settings = settings(order.branch_id)

    with true <- enabled?(order.branch_id),
         stars when stars > 0 <- stars_for(order, settings),
         false <- entry_exists?(order.id, :accrual) do
      now = DateTime.utc_now(:second)

      insert_entry(%{
        client_id: order.client_id,
        branch_id: order.branch_id,
        order_id: order.id,
        kind: :accrual,
        amount: stars,
        remaining: stars,
        expires_at: DateTime.add(now, settings.expire_days, :day)
      })
    else
      _ -> {:ok, nil}
    end
  end

  def spend(%Order{points_spent: stars}) when not is_integer(stars) or stars <= 0, do: {:ok, nil}
  def spend(%Order{client_id: nil}), do: {:error, :points_unavailable}

  def spend(%Order{} = order) do
    Repo.transaction(fn ->
      lock_account(order.client_id)

      if balance(order.client_id) < order.points_spent, do: Repo.rollback(:insufficient_points)

      consume(order.client_id, order.points_spent)

      case insert_entry(%{
             client_id: order.client_id,
             branch_id: order.branch_id,
             order_id: order.id,
             kind: :redeem,
             amount: -order.points_spent
           }) do
        {:ok, entry} -> entry
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def refund(%Order{points_spent: stars}) when not is_integer(stars) or stars <= 0,
    do: {:ok, nil}

  def refund(%Order{} = order) do
    with %Entry{} <- find_entry(order.id, :redeem),
         false <- entry_exists?(order.id, :refund) do
      insert_entry(%{
        client_id: order.client_id,
        branch_id: order.branch_id,
        order_id: order.id,
        kind: :refund,
        amount: order.points_spent,
        remaining: order.points_spent,
        expires_at:
          DateTime.add(DateTime.utc_now(:second), settings(order.branch_id).expire_days, :day)
      })
    else
      _ -> {:ok, nil}
    end
  end

  def reverse(%Order{client_id: nil}), do: {:ok, nil}

  def reverse(%Order{} = order) do
    with %Entry{} = accrual <- find_entry(order.id, :accrual),
         false <- entry_exists?(order.id, :accrual_reversal) do
      Repo.transaction(fn ->
        lock_account(accrual.client_id)
        taken = min(accrual.amount, balance(accrual.client_id))

        Repo.update_all(from(e in Entry, where: e.id == ^accrual.id), set: [remaining: 0])

        case insert_entry(%{
               client_id: accrual.client_id,
               branch_id: accrual.branch_id,
               order_id: order.id,
               kind: :accrual_reversal,
               amount: -taken
             }) do
          {:ok, entry} -> entry
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      _ -> {:ok, nil}
    end
  end

  def adjust(staff, %Branch{} = branch, client_id, amount, reason)
      when is_integer(amount) and amount != 0 do
    with :ok <- Identity.authorize(staff, "clients.update", branch.id),
         true <- String.trim(reason || "") != "" || {:error, :reason_required} do
      Repo.transaction(fn ->
        lock_account(client_id)
        applied = if amount < 0, do: -min(-amount, balance(client_id)), else: amount

        attrs = %{
          client_id: client_id,
          branch_id: branch.id,
          staff_id: staff.id,
          kind: :adjust,
          amount: applied,
          reason: String.trim(reason),
          remaining: max(applied, 0),
          expires_at: expiry(branch, applied)
        }

        case insert_entry(attrs) do
          {:ok, entry} -> entry
          {:error, error} -> Repo.rollback(error)
        end
      end)
      |> Audit.track(staff, "loyalty.adjusted")
    end
  end

  def adjust(_staff, _branch, _client_id, _amount, _reason), do: {:error, :invalid_amount}

  def expire_due(now \\ DateTime.utc_now()) do
    due =
      Repo.all(
        from(e in Entry,
          where: e.kind in [:accrual, :adjust] and e.remaining > 0 and e.expires_at <= ^now,
          order_by: [asc: e.expires_at]
        )
      )

    Enum.reduce(due, 0, fn entry, total ->
      case expire(entry) do
        {:ok, amount} -> total + amount
        _error -> total
      end
    end)
  end

  def summary(branch_id) do
    rows =
      Repo.all(
        from(e in Entry,
          where: e.branch_id == ^branch_id,
          group_by: e.kind,
          select: {e.kind, sum(e.amount)}
        )
      )
      |> Map.new()

    issued = Map.get(rows, :accrual, 0) + positive(Map.get(rows, :adjust, 0))

    %{
      issued: issued,
      reversed: -Map.get(rows, :accrual_reversal, 0),
      expired: -Map.get(rows, :expire, 0),
      liability: Enum.sum(Map.values(rows))
    }
  end

  defp positive(value), do: max(value, 0)

  defp consume(client_id, stars) do
    entries =
      Repo.all(
        from(e in Entry,
          where: e.client_id == ^client_id and e.remaining > 0,
          order_by: [asc_nulls_last: e.expires_at, asc: e.inserted_at]
        )
      )

    Enum.reduce_while(entries, stars, fn
      _entry, 0 ->
        {:halt, 0}

      entry, left ->
        taken = min(entry.remaining, left)
        Repo.update_all(from(e in Entry, where: e.id == ^entry.id), inc: [remaining: -taken])
        {:cont, left - taken}
    end)
  end

  defp expire(entry) do
    Repo.transaction(fn ->
      lock_account(entry.client_id)
      taken = min(entry.remaining, balance(entry.client_id))

      Repo.update_all(from(e in Entry, where: e.id == ^entry.id), set: [remaining: 0])

      if taken > 0 do
        case insert_entry(%{
               client_id: entry.client_id,
               branch_id: entry.branch_id,
               order_id: nil,
               kind: :expire,
               amount: -taken
             }) do
          {:ok, _expired} -> taken
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        0
      end
    end)
  end

  defp expiry(_branch, amount) when amount <= 0, do: nil

  defp expiry(branch, _amount),
    do: DateTime.add(DateTime.utc_now(:second), settings(branch).expire_days, :day)

  defp entry_exists?(order_id, kind),
    do: Repo.exists?(from(e in Entry, where: e.order_id == ^order_id and e.kind == ^kind))

  defp find_entry(order_id, kind),
    do: Repo.one(from(e in Entry, where: e.order_id == ^order_id and e.kind == ^kind))

  defp lock_account(client_id) do
    Repo.insert_all(
      Account,
      [%{client_id: client_id, balance: 0, inserted_at: now(), updated_at: now()}],
      on_conflict: :nothing
    )

    Repo.one(from(a in Account, where: a.client_id == ^client_id, lock: "FOR UPDATE"))
  end

  defp insert_entry(attrs) do
    Repo.transaction(fn ->
      lock_account(attrs.client_id)

      entry =
        case Repo.insert(struct(Entry, attrs)) do
          {:ok, entry} -> entry
          {:error, reason} -> Repo.rollback(reason)
        end

      Repo.update_all(from(a in Account, where: a.client_id == ^attrs.client_id),
        inc: [balance: attrs.amount],
        set: [updated_at: now()]
      )

      entry
    end)
  end

  defp now, do: DateTime.utc_now(:second)
end
