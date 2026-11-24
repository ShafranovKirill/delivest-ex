defmodule DelivestWeb.Hooks.FeatureAccess do
  import Phoenix.LiveView
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Features
  alias DelivestWeb.Staff

  @views %{
    Staff.SegmentLive.Index => "segments",
    Staff.MarketingLive.Index => "marketing_policies",
    Staff.MarketingLive.Hub => "notifications",
    Staff.CourierLive.Index => "couriers",
    Staff.CourierLive.Board => "couriers",
    Staff.DeliveryLive.Couriers => "couriers",
    Staff.ProductLive.Bulk => "product_import",
    Staff.StockLive.Stocks => "stocks",
    Staff.PromotionLive.Promotions => "promotions",
    Staff.LoyaltyLive.Index => "loyalty",
    Staff.KitchenLive.Index => "kitchen",
    Staff.LogLive.Index => "event_log",
    Staff.DiagnosticsLive.Index => "event_log",
    Staff.AdvertisingLive.Index => "analytics_links",
    Staff.AnalyticsLive.Advertising => "yandex_costs"
  }

  def on_mount(:default, params, _session, socket) do
    feature = feature_for(socket.view, params)

    case if(feature, do: require_feature(socket, feature), else: {:cont, socket}) do
      {:cont, socket} ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(Delivest.PubSub, "features:changed")

        {:cont,
         socket
         |> Phoenix.Component.assign(:current_feature_gate, feature)
         |> Phoenix.Component.assign(:capability_revision, 0)
         |> attach_hook(:feature_access, :handle_event, fn _, _, socket ->
           case socket.assigns.current_feature_gate do
             nil -> {:cont, socket}
             current -> require_feature(socket, current)
           end
         end)
         |> attach_hook(:feature_access_params, :handle_params, fn params, _, socket ->
           current = feature_for(socket.view, params)
           socket = Phoenix.Component.assign(socket, :current_feature_gate, current)
           if current, do: require_feature(socket, current), else: {:cont, socket}
         end)
         |> attach_hook(:feature_access_info, :handle_info, fn
           :features_changed, %{view: Staff.SettingsLive.Index} = socket ->
             {:halt, bump_navigation(socket)}

           :features_changed, %{view: Staff.DashboardLive.Index} = socket ->
             {:cont, bump_navigation(socket)}

           :features_changed, socket ->
             socket = bump_navigation(socket)

             case socket.assigns.current_feature_gate do
               nil ->
                 {:halt, socket}

               current ->
                 case require_feature(socket, current) do
                   {:halt, socket} ->
                     {:halt, socket}

                   {:cont, socket} ->
                     {:halt, socket}
                 end
             end

           _, socket ->
             {:cont, socket}
         end)}

      halted ->
        halted
    end
  end

  defp feature_for(Staff.StatisticsLive.Index, %{"section" => section}) do
    case section do
      "funnel" -> "analytics_funnel"
      "channels" -> "analytics_extended"
      "customers" -> "analytics_extended"
      "comparison" -> "analytics_franchise"
      "sources" -> "analytics_links"
      _ -> "analytics_basic"
    end
  end

  defp feature_for(Staff.StatisticsLive.Index, _), do: "analytics_basic"
  defp feature_for(view, _), do: Map.get(@views, view)

  defp bump_navigation(socket) do
    Phoenix.Component.assign(socket, :capability_revision, socket.assigns.capability_revision + 1)
  end

  defp require_feature(socket, feature) do
    scope =
      case socket.assigns[:current_branch] do
        %{id: id} -> {:branch, id}
        _ -> :franchise
      end

    if Features.enabled?(feature, scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, gettext("This capability is disabled"))
       |> redirect(to: "/staff/dashboard")}
    end
  end
end
