defmodule Delivest.Promo.Issuing do
  import Ecto.Query, warn: false

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Identity.Client
  alias Delivest.Promo.{Codes, PromoCode, Promotion}

  @default_uses 1

  def issue(staff, %Promotion{kind: :personal_code} = promotion, %Client{} = client, uses) do
    if Identity.authorize(staff, "promotions.update", promotion.branch_id) == :ok do
      Codes.insert_unique(&build(promotion, client, staff, uses, &1))
      |> preload_client()
    else
      {:error, :forbidden}
    end
    |> Audit.track(staff, "promo_code.issued", metadata: %{client: client.phone})
  end

  def issue(_staff, _promotion, _client, _uses), do: {:error, :not_personal}

  def issue_by_phone(staff, promotion, phone, uses) do
    with {:ok, client} <- Identity.get_or_create_client_by_phone(phone) do
      issue(staff, promotion, client, uses)
    end
  end

  def revoke(staff, %PromoCode{} = code) do
    if Identity.authorize(
         staff,
         "promotions.update",
         Repo.preload(code, :promotion).promotion.branch_id
       ) == :ok do
      Repo.delete(code)
    else
      {:error, :forbidden}
    end
    |> Audit.track(staff, "promo_code.revoked")
  end

  def get_issued(branch_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %PromoCode{} = code <- Repo.get_by(PromoCode, id: uuid, branch_id: branch_id) do
      {:ok, code}
    else
      _ -> {:error, :not_found}
    end
  end

  defp build(promotion, client, staff, uses, code) do
    %PromoCode{
      promotion_id: promotion.id,
      branch_id: promotion.branch_id,
      client_id: client.id,
      issued_by_id: staff.id
    }
    |> PromoCode.changeset(%{code: code, usage_limit: uses || @default_uses})
  end

  defp preload_client({:ok, code}), do: {:ok, Repo.preload(code, :client)}
  defp preload_client(error), do: error
end
