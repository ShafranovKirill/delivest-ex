defmodule DelivestWeb.Hooks.IntegrationAccess do
  import Phoenix.LiveView
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Integrations.StaffAccess
  alias DelivestWeb.Staff.IntegrationLive

  @providers %{
    IntegrationLive.YandexAds => :yandex_ads,
    IntegrationLive.Zvonok => :zvonok,
    IntegrationLive.Dadata => :dadata,
    IntegrationLive.Yookassa => :yookassa,
    IntegrationLive.YandexEda => :yandex_eda,
    IntegrationLive.YandexEdaShared => :yandex_eda,
    IntegrationLive.YandexDelivery => :yandex_delivery,
    IntegrationLive.Fiscal => :atol,
    IntegrationLive.Ycart => :ycart,
    IntegrationLive.Frontpad => :frontpad,
    IntegrationLive.Iiko => :iiko,
    IntegrationLive.Rkeeper => :rkeeper
  }

  def on_mount(:default, _params, _session, socket) do
    case Map.fetch(@providers, socket.view) do
      {:ok, provider} ->
        case require_access(socket, provider) do
          {:cont, socket} ->
            {:cont,
             attach_hook(socket, :integration_access, :handle_event, fn _, _, socket ->
               require_access(socket, provider)
             end)}

          halted ->
            halted
        end

      :error ->
        {:cont, socket}
    end
  end

  defp require_access(socket, provider) do
    if StaffAccess.allowed?(provider) do
      {:cont, socket}
    else
      path =
        case socket.assigns[:current_branch] do
          %{slug: slug} -> "/staff/b/#{slug}/integrations"
          _ -> "/staff/integrations"
        end

      {:halt, socket |> put_flash(:error, gettext("Permission denied")) |> redirect(to: path)}
    end
  end
end
