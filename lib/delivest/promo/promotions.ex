defmodule Delivest.Promo.Promotions do
  import Ecto.Query, warn: false

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Promo.{Catalog, Codes, PromoCode, Promotion, References, Usage}
  alias Ecto.Multi

  def list(staff, branch_id) do
    if Identity.authorize(staff, "promotions.read", branch_id) == :ok do
      promotions =
        from(p in Promotion,
          where: p.branch_id == ^branch_id and is_nil(p.deleted_at),
          order_by: [desc: p.enabled, desc: p.priority, desc: p.inserted_at]
        )
        |> Repo.all()

      {:ok, with_codes(promotions)}
    else
      {:error, :forbidden}
    end
  end

  def usage(promotions),
    do: Usage.load(Enum.map(promotions, & &1.id), nil, [], nil)

  def list_personal(branch_id) do
    from(p in Promotion,
      where: p.branch_id == ^branch_id and p.kind == :personal_code and is_nil(p.deleted_at),
      order_by: [asc: p.name]
    )
    |> Repo.all()
  end

  def list_running(branch_id, now \\ DateTime.utc_now()) do
    from(p in Promotion,
      where:
        p.branch_id == ^branch_id and p.kind == :automatic and p.enabled and
          is_nil(p.deleted_at) and (is_nil(p.starts_at) or p.starts_at <= ^now) and
          (is_nil(p.ends_at) or p.ends_at > ^now),
      order_by: [desc: p.priority, asc: p.name]
    )
    |> Repo.all()
  end

  def get(staff, branch_id, id) do
    with true <-
           Identity.authorize(staff, "promotions.read", branch_id) == :ok || {:error, :forbidden},
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Promotion{} = promotion <- Repo.get_by(Promotion, id: uuid, branch_id: branch_id),
         nil <- promotion.deleted_at do
      {:ok, promotion |> List.wrap() |> with_codes() |> hd()}
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  def change(%Promotion{} = promotion, attrs \\ %{}), do: Promotion.changeset(promotion, attrs)

  def create(staff, branch_id, attrs) do
    authorized(staff, "promotions.create", branch_id, fn ->
      %Promotion{branch_id: branch_id}
      |> Promotion.changeset(attrs)
      |> References.validate(branch_id)
      |> save(&Multi.insert(&1, :promotion, &2))
    end)
    |> Audit.track(staff, "promotion.created", branch_id: branch_id)
  end

  def update(staff, %Promotion{} = promotion, attrs) do
    authorized(staff, "promotions.update", promotion.branch_id, fn ->
      promotion
      |> Promotion.changeset(attrs)
      |> References.validate(promotion.branch_id)
      |> save(&Multi.update(&1, :promotion, &2))
    end)
    |> Audit.track(staff, "promotion.updated", branch_id: promotion.branch_id)
  end

  def toggle(staff, %Promotion{} = promotion) do
    authorized(staff, "promotions.update", promotion.branch_id, fn ->
      promotion |> Promotion.toggle_changeset() |> Repo.update() |> invalidated()
    end)
    |> Audit.track(staff, "promotion.updated", branch_id: promotion.branch_id)
  end

  def delete(staff, %Promotion{} = promotion) do
    authorized(staff, "promotions.delete", promotion.branch_id, fn ->
      promotion |> Promotion.delete_changeset() |> Repo.update() |> invalidated()
    end)
    |> Audit.track(staff, "promotion.deleted", branch_id: promotion.branch_id)
  end

  defp save(%Ecto.Changeset{valid?: false} = changeset, _persist),
    do: {:error, %{changeset | action: :validate}}

  defp save(changeset, persist) do
    Multi.new()
    |> persist.(changeset)
    |> Multi.run(:code, fn _repo, %{promotion: promotion} ->
      upsert_public_code(promotion, Ecto.Changeset.get_field(changeset, :code), changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{promotion: promotion, code: code}} -> invalidated({:ok, %{promotion | code: code}})
      {:error, _step, error, _changes} -> {:error, error}
    end
  end

  defp upsert_public_code(%Promotion{kind: :public_code} = promotion, code, changeset) do
    (Codes.public_code(promotion) ||
       %PromoCode{promotion_id: promotion.id, branch_id: promotion.branch_id})
    |> PromoCode.changeset(%{code: code})
    |> Repo.insert_or_update()
    |> case do
      {:ok, promo_code} -> {:ok, promo_code.code}
      {:error, code_changeset} -> {:error, copy_code_errors(changeset, code_changeset)}
    end
  end

  defp upsert_public_code(_promotion, _code, _changeset), do: {:ok, nil}

  defp copy_code_errors(changeset, code_changeset) do
    code_changeset.errors
    |> Enum.reduce(changeset, fn {_field, {message, opts}}, acc ->
      Ecto.Changeset.add_error(acc, :code, message, opts)
    end)
    |> Map.put(:action, :validate)
  end

  defp with_codes(promotions) do
    ids = for %Promotion{kind: :public_code, id: id} <- promotions, do: id

    codes =
      from(c in PromoCode, where: c.promotion_id in ^ids and is_nil(c.client_id))
      |> Repo.all()
      |> Map.new(&{&1.promotion_id, &1.code})

    Enum.map(promotions, &%{&1 | code: Map.get(codes, &1.id)})
  end

  defp invalidated({:ok, %Promotion{} = promotion} = result) do
    Catalog.invalidate(promotion.branch_id)
    result
  end

  defp invalidated(error), do: error

  defp authorized(staff, permission, branch_id, fun) do
    if Identity.authorize(staff, permission, branch_id) == :ok,
      do: fun.(),
      else: {:error, :forbidden}
  end
end
