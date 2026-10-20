defmodule Delivest.Promo.Codes do
  import Ecto.Query, warn: false

  alias Delivest.Promo.{PromoCode, Promotion}
  alias Delivest.Repo

  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @length 8
  @attempts 5

  def find(nil, _code), do: nil
  def find(_branch_id, nil), do: nil

  def find(branch_id, code) do
    code = PromoCode.normalize(code)

    Repo.one(
      from(c in PromoCode,
        join: p in Promotion,
        on: p.id == c.promotion_id,
        where: c.branch_id == ^branch_id and fragment("upper(?)", c.code) == ^code,
        where: is_nil(p.deleted_at)
      )
    )
  end

  def public_code(%Promotion{id: nil}), do: nil

  def public_code(%Promotion{id: id}) do
    Repo.one(from(c in PromoCode, where: c.promotion_id == ^id and is_nil(c.client_id), limit: 1))
  end

  def list_issued(%Promotion{id: id}) do
    from(c in PromoCode,
      where: c.promotion_id == ^id and not is_nil(c.client_id),
      order_by: [desc: c.inserted_at],
      preload: [:client]
    )
    |> Repo.all()
  end

  def list_for_client(client_id, branch_id) do
    from(c in PromoCode,
      join: p in Promotion,
      on: p.id == c.promotion_id,
      where: c.client_id == ^client_id and c.branch_id == ^branch_id and is_nil(p.deleted_at),
      order_by: [desc: c.inserted_at],
      preload: [promotion: p]
    )
    |> Repo.all()
  end

  def insert_unique(build_changeset, attempts \\ @attempts)

  def insert_unique(build_changeset, attempts) when attempts > 0 do
    case build_changeset.(generate()) |> Repo.insert() do
      {:ok, code} ->
        {:ok, code}

      {:error, %Ecto.Changeset{errors: [code: _]} = changeset} ->
        if attempts > 1,
          do: insert_unique(build_changeset, attempts - 1),
          else: {:error, changeset}

      error ->
        error
    end
  end

  def generate do
    @length
    |> :crypto.strong_rand_bytes()
    |> :binary.bin_to_list()
    |> Enum.map(&Enum.at(@alphabet, rem(&1, length(@alphabet))))
    |> List.to_string()
  end
end
