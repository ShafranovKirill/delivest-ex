defmodule DelivestWeb.Router do
  use DelivestWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DelivestWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug DelivestWeb.Plugs.Locale
  end

  pipeline :staff_browser do
    plug :browser
    plug DelivestWeb.Plugs.FetchCurrentStaff
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: DelivestWeb.OpenApi
  end

  pipeline :client_api do
    plug :api
    plug :fetch_cookies
    plug DelivestWeb.Plugs.EnsureSessionId
  end

  pipeline :client_identity do
    plug DelivestWeb.Plugs.FetchCurrentClient
  end

  pipeline :client_required do
    plug DelivestWeb.Plugs.RequireClient
  end

  pipeline :client_auth_rate_limit do
    plug DelivestWeb.Plugs.RateLimit, bucket: :client_auth, limit: 5, period: :timer.minutes(1)
  end

  pipeline :order_rate_limit do
    plug DelivestWeb.Plugs.RateLimit, bucket: :orders, limit: 10, period: :timer.minutes(1)
  end

  pipeline :cart_rate_limit do
    plug DelivestWeb.Plugs.RateLimit, bucket: :cart, limit: 300, period: :timer.minutes(1)
  end

  pipeline :geo_rate_limit do
    plug DelivestWeb.Plugs.RateLimit, bucket: :geo, limit: 120, period: :timer.minutes(1)
  end

  pipeline :promo_rate_limit do
    plug DelivestWeb.Plugs.RateLimit, bucket: :promo_codes, limit: 10, period: :timer.minutes(1)
  end

  pipeline :login_rate_limit do
    plug DelivestWeb.Plugs.RateLimit,
      bucket: :staff_login,
      limit: 10,
      period: :timer.minutes(1),
      format: :text
  end

  scope "/client/auth", DelivestWeb.Client.Auth do
    pipe_through :client_api

    post "/call/:id/complete", AuthController, :complete
    post "/refresh", AuthController, :refresh

    scope "/" do
      pipe_through :client_auth_rate_limit

      post "/call", AuthController, :start
    end
  end

  scope "/client/geo", DelivestWeb.Client.Geo do
    pipe_through [:api, :geo_rate_limit]

    get "/suggest", GeoController, :suggest
    get "/reverse", GeoController, :reverse
  end

  scope "/client/delivery", DelivestWeb.Client.Delivery do
    pipe_through [:api, :geo_rate_limit]

    get "/quote", DeliveryController, :quote
  end

  scope "/client/franchise", DelivestWeb.Client.Franchise do
    pipe_through :api

    get "/", FranchiseController, :show
    get "/documents/:kind", FranchiseController, :document
  end

  scope "/client", DelivestWeb.Client do
    pipe_through [:client_api, :client_identity, :client_required]

    get "/me", Profile.ProfileController, :show
    get "/orders", Order.OrderController, :index

    scope "/addresses", Address do
      get "/", AddressController, :index
      post "/", AddressController, :create
      put "/:id", AddressController, :update
      delete "/:id", AddressController, :delete
    end
  end

  scope "/client", DelivestWeb.Client do
    pipe_through [:client_api, :client_identity]

    scope "/branches", Branch do
      get "/", BranchController, :index
      post "/:id/select", BranchController, :select
      post "/slug/:slug/select", BranchController, :select_by_slug
      delete "/active", BranchController, :clear_active
    end

    scope "/cart", Cart do
      pipe_through :cart_rate_limit

      get "/", CartController, :show
      post "/:cart_id/items/:product_id", CartController, :add_item
      delete "/:cart_id/items/:product_id", CartController, :remove_item
      delete "/:cart_id/clear", CartController, :clear
      post "/:cart_id/repeat/:order_id", CartController, :repeat
      put "/:cart_id/context", CartController, :update_context
      delete "/:cart_id/promo_code", CartController, :remove_promo_code

      scope "/" do
        pipe_through :promo_rate_limit

        post "/:cart_id/promo_code", CartController, :apply_promo_code
      end
    end

    get "/socket_token", Socket.SocketController, :token
    get "/push/key", Push.PushController, :key
    post "/orders/:order_id/push", Push.PushController, :subscribe

    scope "/orders", Order do
      get "/active", OrderController, :active

      scope "/" do
        pipe_through :order_rate_limit

        post "/", OrderController, :create
      end
    end

    get "/:branch_id/stocks", Stock.StockController, :index
    get "/:branch_id/promotions", Promotion.PromotionController, :index
    get "/branches/:branch_id/menu", Menu.MenuController, :index
  end

  scope "/integrations", DelivestWeb.Integrations do
    pipe_through :api

    post "/crm/:provider/:token", CrmWebhookController, :create
  end

  scope "/integrations", DelivestWeb.Integrations do
    get "/zvonok/:token", ZvonokWebhookController, :create
  end

  pipeline :yandex_eda do
    plug DelivestWeb.Plugs.RateLimit, bucket: :yandex_eda, limit: 600, period: :timer.minutes(1)
    plug DelivestWeb.Plugs.YandexEdaJournal
  end

  pipeline :yandex_eda_auth do
    plug DelivestWeb.Plugs.YandexEdaAuth
  end

  scope "/integrations/yandex-eda", DelivestWeb.Integrations.YandexEda do
    pipe_through :yandex_eda

    post "/security/oauth/token", TokenController, :create

    scope "/" do
      pipe_through :yandex_eda_auth

      get "/restaurants", RestaurantController, :index
      get "/restaurants/availability", RestaurantController, :availability
      get "/places/:restaurant_id/schedule", RestaurantController, :schedule
      get "/menu/:restaurant_id/composition", MenuController, :composition
      get "/menu/:restaurant_id/availability", MenuController, :availability

      post "/order", OrderController, :create
      get "/order/:id", OrderController, :show
      put "/order/:id", OrderController, :update
      delete "/order/:id", OrderController, :delete
      get "/order/:id/status", OrderController, :status
      put "/order/:id/status", OrderController, :update_status
      put "/order/:id/courier", OrderController, :courier
      post "/v1/feedback", OrderController, :feedback
    end
  end

  scope "/staff", DelivestWeb.Staff do
    pipe_through :staff_browser

    scope "/" do
      pipe_through :login_rate_limit
      post "/auth/log_in", StaffSessionController, :create
    end

    delete "/auth/log_out", StaffSessionController, :delete
    get "/branches/select/:branch_id", StaffActiveBranchController, :set

    live_session :staff_public,
      on_mount: [{DelivestWeb.Hooks.StaffAuth, :default}] do
      scope "/auth" do
        pipe_through :browser
        live "/login", AuthLive.Login, :new
      end
    end

    live_session :staff_default,
      layout: {DelivestWeb.Layouts, :staff_app},
      on_mount: [
        {DelivestWeb.Hooks.StaffAuth, :default},
        {DelivestWeb.Hooks.StaffAuth, :require_authenticated_staff},
        {DelivestWeb.Hooks.StaffActiveBranch, :optional},
        {DelivestWeb.Hooks.NewOrders, :default},
        {DelivestWeb.Hooks.StaffPath, :default}
      ] do
      live "/branches/select", BranchLive.BranchSelect, :index

      scope "/branches", BranchLive do
        live "/", Branches, :index
        live "/new", Edit, :new
        live "/:slug/edit", Edit, :edit
      end

      scope "/employee", StaffLive do
        live "/", Staffs, :index
        live "/:id/edit", Staffs, :edit
        live "/new", Staffs, :new
      end

      scope "/franchise", FranchiseLive do
        live "/", Index, :index
        live "/documents/:kind", Index, :document
      end

      scope "/roles", RoleLive do
        live "/", Roles, :index
        live "/:id/edit", Roles, :edit
        live "/new", Roles, :new
      end

      scope "/clients", ClientLive do
        live "/", Clients, :index
        live "/new", Clients, :new
        live "/:id", Show, :show
        live "/:id/edit", Clients, :edit
      end

      scope "/logs", LogLive do
        live "/", Index, :events
        live "/raw", Index, :raw
        live "/errors", Index, :errors
      end
    end

    live_session :staff_need_branch,
      layout: {DelivestWeb.Layouts, :staff_app},
      on_mount: [
        {DelivestWeb.Hooks.StaffAuth, :default},
        {DelivestWeb.Hooks.StaffAuth, :require_authenticated_staff},
        {DelivestWeb.Hooks.StaffActiveBranch, :default},
        {DelivestWeb.Hooks.NewOrders, :default},
        {DelivestWeb.Hooks.StaffPath, :default}
      ] do
      live "/dashboard", DashboardLive.Index, :index
      live "/statistics", StatisticsLive.Index, :index
      live "/delivery", DeliveryLive.Index, :index

      scope "/integrations", IntegrationLive do
        live "/", Index, :index
        live "/frontpad", Frontpad, :index
        live "/routes", Routes, :index
        live "/zvonok", Zvonok, :index
        live "/dadata", Dadata, :index
        live "/yandex-eda", YandexEda, :index
      end

      scope "/categories", CategoryLive do
        live "/", Categories, :index
        live "/:id/edit", Categories, :edit
        live "/:id/products", Categories, :products
        live "/new", Categories, :new
      end

      scope "/products", ProductLive do
        live "/", Products, :index
        live "/bulk", Bulk, :index
        live "/tags", Tags, :index
        live "/tags/new", Tags, :new
        live "/tags/:id/edit", Tags, :edit
        live "/:id/edit", Products, :edit
        live "/new", Products, :new
      end

      scope "/stocks", StockLive do
        live "/", Stocks, :index
        live "/:id/edit", Stocks, :edit
        live "/new", Stocks, :new
      end

      scope "/promotions", PromotionLive do
        live "/", Promotions, :index
        live "/new", Promotions, :new
        live "/sale", Promotions, :sale
        live "/:id/edit", Promotions, :edit
        live "/:id/codes", Promotions, :codes
      end

      scope "/orders", OrderLive do
        live "/", Orders, :index
        live "/new", OrderForm, :new
        live "/:id/edit", OrderForm, :edit
      end
    end
  end

  scope "/seo", DelivestWeb.Seo do
    get "/head", SeoController, :head
    get "/robots.txt", SeoController, :robots
    get "/sitemap.xml", SeoController, :sitemap
    get "/site.webmanifest", SeoController, :manifest
    get "/favicon.ico", SeoController, :favicon
  end

  scope "/" do
    pipe_through :staff_browser

    get "/", DelivestWeb.PageController, :home
  end

  scope "/" do
    pipe_through :browser

    get "/locale/:locale", DelivestWeb.Staff.StaffLocaleController, :set
    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, spec: DelivestWeb.OpenApi
  end

  if Application.compile_env(:delivest, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DelivestWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
