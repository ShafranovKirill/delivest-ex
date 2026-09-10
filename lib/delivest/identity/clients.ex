defmodule Delivest.Identity.Clients do
  import Ecto.Query
  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Client

  @spec list_clients(map(), map()) ::
          {:ok, {[Client.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()} | {:error, :forbidden}
  def list_clients(staff, params \\ %{}) do
    if Identity.can?(staff, "clients.read") do
      query = where(Client, [c], is_nil(c.deleted_at))

      Flop.validate_and_run(query, params, for: Client)
    else
      {:error, :forbidden}
    end
  end

  @spec get_client(map(), String.t()) ::
          {:ok, Client.t()} | {:error, :not_found} | {:error, :forbidden}
  def get_client(staff, id) do
    if Identity.can?(staff, "clients.read") do
      Client
      |> where([c], is_nil(c.deleted_at))
      |> Repo.get(id)
      |> case do
        nil -> {:error, :not_found}
        client -> {:ok, client}
      end
    else
      {:error, :forbidden}
    end
  end

  @spec get_or_create_client_by_phone(String.t(), map()) ::
          {:ok, Client.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_client_by_phone(phone, attrs \\ %{}) do
    case get_active_client_by_phone(phone) do
      %Client{} = client ->
        update_client_if_changed(client, attrs)

      nil ->
        create_client(Map.put(attrs, :phone, phone))
    end
  end

  @spec create_client(map()) :: {:ok, Client.t()} | {:error, Ecto.Changeset.t()}
  def create_client(attrs) do
    %Client{}
    |> Client.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_client(map(), Client.t(), map()) ::
          {:ok, Client.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def update_client(staff, %Client{} = client, attrs) do
    if Identity.can?(staff, "clients.update") do
      client
      |> Client.changeset(attrs)
      |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  @spec soft_delete_client(map(), Client.t()) ::
          {:ok, Client.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def soft_delete_client(staff, %Client{} = client) do
    if Identity.can?(staff, "clients.delete") do
      client
      |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now(:second)})
      |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  @spec get_clients_map([String.t()]) :: %{String.t() => Client.t()}
  def get_clients_map(ids) when is_list(ids) do
    Client
    |> where([c], c.id in ^ids)
    |> where([c], is_nil(c.deleted_at))
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @spec search_clients(map(), String.t(), integer()) :: [Client.t()] | {:error, :forbidden}
  def search_clients(staff, query, limit \\ 10) do
    if Identity.can?(staff, "clients.read") do
      search_term = "%#{query}%"

      Client
      |> where([c], is_nil(c.deleted_at))
      |> where([c], ilike(c.name, ^search_term) or ilike(c.phone, ^search_term))
      |> limit(^limit)
      |> Repo.all()
    else
      {:error, :forbidden}
    end
  end

  @spec get_client_ids_by_search(String.t()) :: [String.t()]
  def get_client_ids_by_search(query) do
    search_term = "%#{query}%"

    Client
    |> where([c], is_nil(c.deleted_at))
    |> where([c], ilike(c.name, ^search_term) or ilike(c.phone, ^search_term))
    |> select([c], c.id)
    |> Repo.all()
  end

  defp get_active_client_by_phone(phone) do
    Client
    |> where([c], c.phone == ^phone)
    |> where([c], is_nil(c.deleted_at))
    |> Repo.one()
  end

  defp update_client_if_changed(%Client{} = client, attrs) do
    sanitized_attrs = Map.drop(attrs, [:phone, "phone"])

    client
    |> Client.changeset(sanitized_attrs)
    |> Repo.update()
  end
end
