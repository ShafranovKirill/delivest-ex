defmodule Delivest.Integrations.YandexEda do
  @behaviour Delivest.Integrations.Channels.Channel

  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.Channels.Products

  alias Delivest.Integrations.YandexEda.{
    BranchSettings,
    Menu,
    MenuReloadWorker,
    OrderEvents,
    OrderIntake,
    OrderLookup,
    OrderRequest,
    OrderStatus,
    Places,
    Schedule,
    Settings,
    StopList,
    Token
  }

  @menu_delay 10

  @impl true
  def key, do: :yandex_eda

  @impl true
  def name, do: "Яндекс Еда"

  @impl true
  def settings_schema, do: BranchSettings

  @impl true
  def configured?(%BranchSettings{enabled: enabled}), do: enabled
  def configured?(_settings), do: false

  @impl true
  def stops_changed(branch_id), do: reload_menu(branch_id, "menu_stop_list")

  @impl true
  def menu_changed(branch_id), do: reload_menu(branch_id, "menu", schedule_in: @menu_delay)

  def get_branch_settings(branch_id) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, branch} -> Places.settings(branch) || %BranchSettings{}
      _error -> %BranchSettings{}
    end
  end

  def change_branch_settings(%BranchSettings{} = settings, attrs \\ %{}),
    do: BranchSettings.changeset(settings, attrs)

  def update_branch_settings(staff, branch_id, attrs) do
    with {:ok, branch} <- Identity.get_branch(branch_id, preload: [:info]),
         {:ok, branch} <-
           Identity.update_branch(staff, branch, %{}, %{"channels" => %{"yandex_eda" => attrs}}) do
      menu_changed(branch.id)
      {:ok, Places.settings(branch)}
    else
      {:error, :info, changeset} -> {:error, nested_changeset(changeset)}
      {:error, _step, changeset} -> {:error, changeset}
      error -> error
    end
  end

  defp nested_changeset(changeset) do
    changeset
    |> Ecto.Changeset.get_change(:channels)
    |> Ecto.Changeset.get_change(:yandex_eda)
  end

  def menu(branch_id) do
    with {:ok, branch} <- Identity.get_branch(branch_id, preload: [:info]),
         do: {:ok, Menu.catalog(branch, get_branch_settings(branch_id))}
  end

  def update_product(staff, product_id, attrs) do
    with {:ok, channel_product} <- Products.update(staff, key(), product_id, attrs) do
      Enum.each(Places.list(), &menu_changed(&1.id))
      {:ok, channel_product}
    end
  end

  def get_settings, do: Repo.one(Settings) || %Settings{}

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, attrs) do
    if Identity.can?(staff, "admin"),
      do: get_settings() |> Settings.changeset(attrs) |> Repo.insert_or_update(),
      else: {:error, :forbidden}
  end

  def rotate_credentials(staff) do
    if Identity.can?(staff, "admin"),
      do: get_settings() |> Settings.changeset(%{}) |> Repo.insert_or_update() |> rotate(),
      else: {:error, :forbidden}
  end

  def issue_token(client_id, client_secret) do
    settings = get_settings()

    if Settings.credentials?(settings) and
         Plug.Crypto.secure_compare(settings.client_id, to_string(client_id)) and
         Plug.Crypto.secure_compare(settings.client_secret, to_string(client_secret)),
       do: {:ok, Token.issue(settings)},
       else: {:error, :invalid_client}
  end

  def valid_token?(token), do: Token.valid?(get_settings(), token)

  def restaurants, do: Enum.map(Places.list(), &Places.view/1)

  def restaurants_availability, do: Enum.map(Places.list(), &Places.availability/1)

  def composition(restaurant_id) do
    with {:ok, branch, settings} <- Places.fetch(restaurant_id),
         do: {:ok, Menu.composition(branch, settings)}
  end

  def availability(restaurant_id) do
    with {:ok, branch, _settings} <- Places.fetch(restaurant_id),
         do: {:ok, StopList.availability(branch.id)}
  end

  def schedule(restaurant_id) do
    with {:ok, branch, _settings} <- Places.fetch(restaurant_id),
         do: {:ok, Schedule.build(branch.info.working_hours)}
  end

  def create_order(params) do
    with {:ok, request} <- OrderRequest.parse(params), do: OrderIntake.create(request)
  end

  def get_order(order_id), do: OrderLookup.fetch(order_id)

  def order_status(order_id) do
    with {:ok, order} <- OrderLookup.fetch(order_id), do: {:ok, OrderStatus.report(order)}
  end

  def cancel_order(order_id, comment) do
    with {:ok, order} <- OrderLookup.fetch(order_id), do: OrderEvents.cancel(order, comment)
  end

  def update_order_status(order_id, params) do
    with {:ok, order} <- OrderLookup.fetch(order_id), do: OrderEvents.status(order, params)
  end

  def update_courier(order_id, params) do
    with {:ok, order} <- OrderLookup.fetch(order_id), do: OrderEvents.courier(order, params)
  end

  def base_url, do: DelivestWeb.Endpoint.url() <> "/integrations/yandex-eda"

  defp reload_menu(branch_id, operation, opts \\ []) do
    if get_branch_settings(branch_id).enabled,
      do:
        %{"branch_id" => branch_id, "operation" => operation}
        |> MenuReloadWorker.new(opts)
        |> Oban.insert()

    :ok
  end

  defp rotate({:ok, settings}), do: settings |> Settings.rotate() |> Repo.update()
  defp rotate(error), do: error
end
