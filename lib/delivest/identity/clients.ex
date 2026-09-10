defmodule Delivest.Identity.Clients do
  import Ecto.Query
  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Client

  @spec list_clients(map(), map(), keyword()) ::
          {:ok, {[Client.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()} | {:error, :forbidden}
  def list_clients(staff, params \\ %{}, opts \\ []) do
    if Identity.can?(staff, "clients.read") do
      query =
        Client
        |> where([c], is_nil(c.deleted_at))
        |> maybe_preload_query(opts)

      Flop.validate_and_run(query, params, for: Client)
    else
      {:error, :forbidden}
    end
  end

  @spec get_client(map(), String.t(), keyword()) ::
          {:ok, Client.t()} | {:error, :not_found} | {:error, :forbidden}
  def get_client(staff, id, opts \\ []) do
    if Identity.can?(staff, "clients.read") do
      Client
      |> where([c], is_nil(c.deleted_at))
      |> maybe_preload_query(opts)
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
        maybe_update_client_name(client, attrs)

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

  defp maybe_update_client_name(%Client{name: nil} = client, %{name: name})
       when is_binary(name) and name != "" do
    update_client_internal(client, %{name: name})
  end

  defp maybe_update_client_name(%Client{name: nil} = client, %{"name" => name})
       when is_binary(name) and name != "" do
    update_client_internal(client, %{name: name})
  end

  defp maybe_update_client_name(client, _attrs), do: {:ok, client}

  defp update_client_internal(client, attrs) do
    client
    |> Client.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_preload_query(query, opts) do
    case Keyword.get(opts, :preload) do
      nil -> query
      preloads -> preload(query, ^preloads)
    end
  end
end
