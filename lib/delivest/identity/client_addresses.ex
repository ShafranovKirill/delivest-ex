defmodule Delivest.Identity.ClientAddresses do
  import Ecto.Query

  alias Delivest.Identity.Client.Address
  alias Delivest.Repo

  @spec list(String.t()) :: [Address.t()]
  def list(client_id) do
    Address
    |> where([a], a.client_id == ^client_id)
    |> order_by([a], desc: a.updated_at)
    |> Repo.all()
  end

  @spec get(String.t(), String.t()) :: {:ok, Address.t()} | {:error, :not_found}
  def get(client_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Address{} = address <- Repo.get_by(Address, id: id, client_id: client_id) do
      {:ok, address}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec create(String.t(), map()) :: {:ok, Address.t()} | {:error, Ecto.Changeset.t()}
  def create(client_id, attrs) do
    %Address{client_id: client_id}
    |> Address.changeset(attrs)
    |> Repo.insert()
  end

  @spec update(Address.t(), map()) :: {:ok, Address.t()} | {:error, Ecto.Changeset.t()}
  def update(%Address{} = address, attrs) do
    address
    |> Address.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(Address.t()) :: {:ok, Address.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Address{} = address), do: Repo.delete(address)

  @spec remember(String.t(), map()) :: {:ok, Address.t()} | {:error, Ecto.Changeset.t()}
  def remember(client_id, attrs) do
    changeset = Address.changeset(%Address{client_id: client_id}, attrs)

    case find_same(client_id, changeset) do
      %Address{} = address -> address |> Address.changeset(attrs) |> Repo.update(force: true)
      nil -> Repo.insert(changeset)
    end
  end

  defp find_same(_client_id, %Ecto.Changeset{valid?: false}), do: nil

  defp find_same(client_id, changeset) do
    Address.identity_fields()
    |> Enum.reduce(where(Address, [a], a.client_id == ^client_id), fn field, query ->
      match_field(query, field, Ecto.Changeset.get_field(changeset, field))
    end)
    |> limit(1)
    |> Repo.one()
  end

  defp match_field(query, field, nil), do: where(query, [a], is_nil(field(a, ^field)))
  defp match_field(query, field, value), do: where(query, [a], field(a, ^field) == ^value)
end
