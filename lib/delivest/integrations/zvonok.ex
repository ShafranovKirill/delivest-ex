defmodule Delivest.Integrations.Zvonok do
  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.Health
  alias Delivest.Integrations.Zvonok.{Api, Settings}

  @spec request_call(String.t()) ::
          {:ok, %{call_id: String.t(), call_number: String.t()}} | {:error, term()}
  def request_call(phone) do
    with {:ok, settings} <- fetch_settings() do
      settings |> Api.confirm(phone) |> track()
    end
  end

  def health_check(settings),
    do: if(Settings.complete?(settings), do: :ok, else: {:error, :zvonok_not_configured})

  defp track({:ok, _call} = result) do
    Health.recovered(:zvonok, nil)
    result
  end

  defp track({:error, reason} = error) do
    Health.report(:zvonok, nil, __MODULE__, {:error, reason})
    error
  end

  @spec valid_webhook_token?(String.t()) :: boolean()
  def valid_webhook_token?(token) do
    case fetch_settings() do
      {:ok, settings} -> Plug.Crypto.secure_compare(settings.webhook_token, token)
      _ -> false
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

  def configured?, do: Settings.complete?(get_settings())

  def enabled?, do: get_settings().enabled

  def webhook_url(token),
    do:
      DelivestWeb.Endpoint.url() <>
        "/integrations/zvonok/" <> token <> "?call_id={ct_call_id}&phone={ct_phone}"

  defp fetch_settings do
    settings = get_settings()

    if Settings.complete?(settings),
      do: {:ok, settings},
      else: {:error, :zvonok_not_configured}
  end
end
