defmodule Delivest.Integrations.Crm.Lookup do
  import Ecto.Query, warn: false

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Oms.Order
  alias Delivest.Repo

  def branch_info_by_webhook_token(provider, token) when is_binary(token) and token != "" do
    query =
      from(i in BranchInfo,
        where: fragment("?->?->>'webhook_token' = ?", i.crm, ^to_string(provider), ^token)
      )

    found(Repo.one(query))
  end

  def branch_info_by_webhook_token(_provider, _token), do: {:error, :not_found}

  def branch_info(branch_id), do: found(Repo.get_by(BranchInfo, branch_id: branch_id))

  def crm_branch_ids do
    from(i in BranchInfo, where: fragment("?->>'enabled' = 'true'", i.crm), select: i.branch_id)
    |> Repo.all()
  end

  def order_by_external_id(branch_id, provider, external_id) do
    query =
      from(o in Order,
        where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
        where: fragment("?->>'provider' = ?", o.crm, ^to_string(provider)),
        where: fragment("?->>'external_id' = ?", o.crm, ^to_string(external_id))
      )

    found(Repo.one(query))
  end

  defp found(nil), do: {:error, :not_found}
  defp found(record), do: {:ok, record}
end
