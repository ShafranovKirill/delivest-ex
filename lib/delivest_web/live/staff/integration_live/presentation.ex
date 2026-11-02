defmodule DelivestWeb.Staff.IntegrationLive.Presentation do
  @moduledoc """
  Computes the three independent integration facts shown to staff:

    * credentials completeness,
    * the result of an explicit connection check,
    * what the integration actually does for the current branch.

  A saved key is never treated as enabled usage, and a successful check never
  enables sending, receiving, payments or synchronisation.
  """

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.{Fiscal}
  alias Delivest.Identity.Branch.PaymentSettings

  alias Delivest.Integrations.{
    Channels,
    Crm,
    Dadata,
    Health,
    YandexDelivery,
    YandexEda,
    Yookassa,
    Zvonok
  }

  alias Delivest.Integrations.Crm.BranchSettings
  alias Delivest.Integrations.Health.Status

  @shared [:zvonok, :dadata, :yookassa]
  @crm_providers [:frontpad, :iiko, :rkeeper]

  def shared?(provider), do: provider in @shared

  def state(provider, %{info: info} = branch) do
    info = info || %{}
    crm = Map.get(info, :crm) || %BranchSettings{}
    credentials = credentials(provider, branch, info)
    status = Health.get(provider, connection_scope(provider, branch))

    %{
      provider: provider,
      scope: scope(provider, branch),
      credentials: credentials,
      connection: connection(status),
      usage: usage(provider, branch, info, crm, credentials),
      warnings: warnings(status)
    }
  end

  def state(provider, branch, crm) do
    credentials = credentials(provider, branch, branch.info || %{})
    status = Health.get(provider, connection_scope(provider, branch))

    %{
      provider: provider,
      scope: scope(provider, branch),
      credentials: credentials,
      connection: connection(status),
      usage: usage(provider, branch, branch.info || %{}, crm, credentials),
      warnings: warnings(status)
    }
  end

  def connection_scope(provider, _branch) when provider in @shared, do: nil
  def connection_scope(:yandex_eda, _branch), do: nil
  def connection_scope(_provider, branch), do: branch.id

  ## Credentials

  def credentials(provider, branch, info \\ nil) do
    info = info || branch.info || %{}

    {items, required?} = credential_items(provider, branch, info)
    items = Enum.reject(items, fn {_label, value} -> blank?(value) end)
    total = length(credential_items(provider, branch, info) |> elem(0))
    filled = length(items)
    missing = credential_missing(provider, branch, info)

    state =
      cond do
        not required? -> :not_required
        filled == 0 -> :missing
        filled < total -> :partial
        true -> :complete
      end

    %{
      state: state,
      filled: filled,
      total: total,
      missing: missing,
      text: credentials_text(state, filled, total)
    }
  end

  defp credential_missing(provider, branch, info) do
    {items, required?} = credential_items(provider, branch, info)

    if required?,
      do: for({label, value} <- items, blank?(value), do: label),
      else: []
  end

  defp credential_items(:frontpad, _branch, info) do
    settings = crm_provider(info, :frontpad)
    {[{gettext("API key"), settings.api_key}], true}
  end

  defp credential_items(:iiko, _branch, info) do
    settings = crm_provider(info, :iiko)

    {[
       {gettext("API key"), settings.api_key},
       {gettext("Organization"), settings.organization_id},
       {gettext("Terminal group"), settings.terminal_group_id}
     ], true}
  end

  defp credential_items(:rkeeper, _branch, info) do
    settings = crm_provider(info, :rkeeper)
    {[{gettext("Restaurant objectId"), settings.object_id}], true}
  end

  defp credential_items(:yookassa, _branch, _info) do
    settings = Yookassa.get_settings()

    {[
       {gettext("Shop ID"), settings.shop_id},
       {gettext("Secret key"), settings.secret_key}
     ], true}
  end

  defp credential_items(:zvonok, _branch, _info) do
    settings = Zvonok.get_settings()

    {[
       {gettext("API key"), settings.public_key},
       {gettext("Campaign ID"), settings.campaign_id},
       {gettext("Webhook token"), settings.webhook_token}
     ], true}
  end

  defp credential_items(:dadata, _branch, _info) do
    {[{gettext("API key"), Dadata.get_settings().api_key}], true}
  end

  defp credential_items(:yandex_eda, _branch, _info) do
    settings = YandexEda.get_settings()

    {[
       {gettext("Client ID"), settings.client_id},
       {gettext("Client secret"), settings.client_secret}
     ], true}
  end

  defp credential_items(:yandex_delivery, _branch, info) do
    settings = Map.get(info, :yandex_delivery) || %YandexDelivery.Settings{}

    {[
       {gettext("OAuth token"), settings.token},
       {gettext("Email"), settings.contact_email}
     ], true}
  end

  defp credential_items(:atol, branch, _info) do
    fiscal = Fiscal.settings(branch.id)

    if fiscal.mode == :own do
      {[
         {gettext("Login"), fiscal.atol && fiscal.atol.login},
         {gettext("Password"), fiscal.atol && fiscal.atol.password},
         {gettext("Group code"), fiscal.atol && fiscal.atol.group_code}
       ], true}
    else
      {[], false}
    end
  end

  defp credential_items(_provider, _branch, _info), do: {[], false}

  defp crm_provider(info, provider) do
    crm = Map.get(info, :crm) || %BranchSettings{}
    Map.get(crm, provider) || module_for(provider).__struct__()
  end

  defp module_for(:frontpad), do: Delivest.Integrations.Frontpad.Settings
  defp module_for(:iiko), do: Delivest.Integrations.Iiko.Settings
  defp module_for(:rkeeper), do: Delivest.Integrations.Rkeeper.Settings

  defp credentials_text(:not_required, _filled, _total),
    do: gettext("Not required in the current mode")

  defp credentials_text(:missing, _filled, _total), do: gettext("Not filled in")
  defp credentials_text(:complete, _filled, _total), do: gettext("Filled in")

  defp credentials_text(:partial, filled, total),
    do: gettext("Partially filled in (%{filled} of %{total})", filled: filled, total: total)

  ## Connection

  def connection(nil), do: connection_map(:unchecked, nil)

  def connection(%Status{checked_at: nil} = status),
    do: connection_map(:unchecked, nil) |> Map.put(:warning, status.warning)

  def connection(%Status{status: :ok} = status),
    do: connection_map(:ok, status)

  def connection(%Status{status: :auth} = status),
    do: connection_map(:auth, status)

  def connection(%Status{status: :failed} = status),
    do: connection_map(:failed, status)

  # Legacy rows created before warnings were split.
  def connection(%Status{status: :warning} = status),
    do: connection_map(:unchecked, nil) |> Map.put(:warning, status.message)

  defp connection_map(state, status) do
    %{
      state: state,
      status: status,
      checked_at: status && status.checked_at,
      warning: status && status.warning,
      text: connection_text(state)
    }
  end

  def connection_text(:ok), do: gettext("Connection checked")
  def connection_text(:auth), do: gettext("Access error")
  def connection_text(:failed), do: gettext("No connection")
  def connection_text(:unchecked), do: gettext("Connection not checked")

  ## Warnings

  def warnings(%Status{warning: warning}) when is_binary(warning) and warning != "" do
    [%{text: warning_text(warning)}]
  end

  def warnings(_status), do: []

  def warning_text("catalog_issues:" <> count),
    do: gettext("The menu differs from the CRM: %{count}", count: count)

  def warning_text("reconcile_issues:" <> count),
    do: gettext("Payments differ from YooKassa: %{count}", count: count)

  def warning_text("kkt_issues:" <> codes) do
    texts =
      codes
      |> String.split(",", trim: true)
      |> Enum.map(&kkt_issue_text/1)

    gettext("Cash register: %{issues}", issues: Enum.join(texts, ", "))
  end

  def warning_text(_warning), do: gettext("Needs attention")

  defp kkt_issue_text("offline"),
    do: gettext("the register is not sending documents to the OFD")

  defp kkt_issue_text("fn_full"), do: gettext("the fiscal storage is more than 90% full")

  defp kkt_issue_text("fn_expiring"),
    do: gettext("the fiscal storage expires in less than 30 days")

  defp kkt_issue_text(_code), do: gettext("needs attention")

  ## Usage

  def usage(provider, _branch, _info, crm, credentials) when provider in @crm_providers do
    crm_usage(provider, crm, credentials)
  end

  def usage(:yookassa, _branch, info, _crm, _credentials) do
    online = (Map.get(info, :payments) || %PaymentSettings{}).online

    [
      item(
        gettext("Online payment in the branch"),
        cond do
          not Yookassa.configured?() -> :not_ready
          online -> :on
          true -> :off
        end,
        cond do
          not Yookassa.configured?() -> gettext("Fill in the shop keys")
          online -> nil
          true -> gettext("Off in Finance → Payment")
        end
      )
    ]
  end

  def usage(:zvonok, _branch, _info, _crm, credentials) do
    settings = Zvonok.get_settings()

    [
      item(
        gettext("Customer sign-in by call"),
        cond do
          not settings.enabled -> :off
          credentials.state != :complete -> :not_ready
          true -> :on
        end,
        cond do
          not settings.enabled -> gettext("Turned off in the settings")
          credentials.state != :complete -> gettext("Fill in the keys and the campaign")
          true -> nil
        end
      )
    ]
  end

  def usage(:dadata, _branch, _info, _crm, credentials) do
    settings = Dadata.get_settings()

    [
      item(
        gettext("Address suggestions"),
        if(credentials.state == :complete and settings.enabled, do: :on, else: :off),
        cond do
          credentials.state != :complete -> gettext("Fill in the API key")
          not settings.enabled -> gettext("The key is saved, suggestions are off")
          true -> nil
        end
      )
    ]
  end

  def usage(:yandex_eda, branch, _info, _crm, _credentials) do
    settings = YandexEda.get_branch_settings(branch.id)

    busy =
      if settings.enabled do
        case YandexEda.busy_mode(branch.id) do
          %{extra_minutes: minutes} -> minutes
          _other -> nil
        end
      end

    [
      item(
        gettext("Taking orders from Yandex Eda"),
        if(settings.enabled, do: :on, else: :off),
        if(settings.enabled, do: nil, else: gettext("Turned off for this branch"))
      ),
      item(
        gettext("Operational pause"),
        if(busy, do: :paused, else: :off),
        if(busy, do: gettext("Paused for %{minutes} min", minutes: busy), else: nil)
      )
    ]
  end

  def usage(:yandex_delivery, _branch, info, _crm, credentials) do
    source = (Map.get(info, :couriers) || %Delivest.Identity.Branch.CourierSettings{}).source

    [
      item(
        gettext("Automatic courier call"),
        cond do
          source != :yandex -> :off
          credentials.state != :complete -> :not_ready
          true -> :on
        end,
        cond do
          source != :yandex -> gettext("The branch uses its own couriers")
          credentials.state != :complete -> gettext("Fill in the token and the email")
          true -> nil
        end
      )
    ]
  end

  def usage(:atol, branch, _info, _crm, credentials) do
    fiscal = Fiscal.settings(branch.id)

    case fiscal.mode do
      :own ->
        [
          item(
            gettext("Receipts from our register"),
            if(credentials.state == :complete, do: :on, else: :not_ready),
            if(credentials.state == :complete,
              do: nil,
              else: gettext("Fill in the ATOL credentials")
            )
          )
        ]

      :external ->
        [
          item(
            gettext("Receipts from our register"),
            :off,
            gettext("Receipts are issued by the CRM or POS")
          )
        ]

      :off ->
        [item(gettext("Receipts from our register"), :off, gettext("Receipts are off"))]
    end
  end

  def usage(_provider, _branch, _info, _crm, _credentials), do: []

  defp crm_usage(provider, crm, credentials) do
    active = BranchSettings.active_provider(crm)
    sending? = crm.enabled == true and crm.provider == provider
    sources = crm.sources || []
    other = active && active != provider && Crm.provider_name(active)
    settings = Map.get(crm, provider)

    [
      item(
        gettext("Sending new orders"),
        cond do
          sending? and credentials.state != :complete -> :not_ready
          sending? and sources == [] -> :not_ready
          sending? -> :on
          true -> :off
        end,
        cond do
          sending? and credentials.state != :complete ->
            gettext("Enabled but not ready: fill in %{fields}",
              fields: Enum.join(credentials.missing, ", ")
            )

          sending? and sources == [] ->
            gettext("No order sources selected — new orders are not sent")

          sending? ->
            nil

          other ->
            gettext("Sending to %{provider}: off. Selected CRM: %{crm}",
              provider: Crm.provider_name(provider),
              crm: other
            )

          true ->
            gettext("You can check the connection and match the menu. New orders are not sent.")
        end
      ),
      item(
        gettext("Order sources"),
        if(sources == [], do: :off, else: :on),
        if(sources == [],
          do: gettext("No order sources selected"),
          else: Enum.map_join(sources, ", ", &source_label/1)
        )
      ),
      item(
        gettext("Menu source"),
        if(crm.menu_source == :crm and active == provider, do: :on, else: :off),
        cond do
          crm.menu_source == :crm and active == provider ->
            gettext("The menu is taken from the CRM")

          crm.menu_source == :crm and other ->
            gettext("The menu is taken from %{crm}", crm: other)

          true ->
            gettext("Own menu, the CRM is only checked")
        end
      ),
      item(
        gettext("Stop list sync"),
        cond do
          is_nil(settings) or not Map.get(settings, :sync_stops) -> :off
          sending? -> :on
          true -> :not_ready
        end,
        cond do
          is_nil(settings) or not Map.get(settings, :sync_stops) ->
            gettext("Automatic sync is off")

          sending? ->
            nil

          true ->
            gettext("Not working: sending to this CRM is off")
        end
      )
    ]
  end

  defp source_label("app"), do: gettext("App")
  defp source_label("staff"), do: gettext("Admin")
  defp source_label("pos"), do: gettext("POS")
  defp source_label(source), do: Channels.name(source)

  defp item(label, state, detail), do: %{label: label, state: state, detail: detail}

  ## Scope

  def scope(provider, _branch) when provider in @shared, do: {:network, nil}
  def scope(:yandex_eda, branch), do: {:network, branch.name}
  def scope(_provider, branch), do: {:branch, branch.name}

  def scope_text({:network, nil}), do: gettext("All branches")

  def scope_text({:network, branch_name}),
    do: gettext("All branches · branch: %{name}", name: branch_name)

  def scope_text({:branch, name}), do: gettext("Branch: %{name}", name: name)

  defp blank?(value), do: value in [nil, ""]
end
