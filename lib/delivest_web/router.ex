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
      put "/:cart_id/context", CartController, :update_context
      delete "/:cart_id/promo_code", CartController, :remove_promo_code

      scope "/" do
        pipe_through :promo_rate_limit

        post "/:cart_id/promo_code", CartController, :apply_promo_code
      end
    end

    get "/socket_token", Socket.SocketController, :token

    scope "/orders", Order do
      get "/active", OrderController, :active

      scope "/" do
        pipe_through :order_rate_limit

        post "/", OrderController, :create
      end
    end

    get "/:branch_id/stocks", Stock.StockController, :index
    get "/branches/:branch_id/menu", Menu.MenuController, :index
  end

  scope "/integrations", DelivestWeb.Integrations do
    pipe_through :api

    post "/frontpad/:token", FrontpadWebhookController, :create
  end

  scope "/integrations", DelivestWeb.Integrations do
    get "/zvonok/:token", ZvonokWebhookController, :create
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
        live "/hints", Index, :hints
      end
    end

    live_session :staff_need_branch,
      layout: {DelivestWeb.Layouts, :staff_app},
      on_mount: [
        {DelivestWeb.Hooks.StaffAuth, :default},
        {DelivestWeb.Hooks.StaffAuth, :require_authenticated_staff},
        {DelivestWeb.Hooks.StaffActiveBranch, :default},
        {DelivestWeb.Hooks.StaffPath, :default}
      ] do
      live "/dashboard", DashboardLive.Index, :index
      live "/statistics", StatisticsLive.Index, :index

      scope "/categories", CategoryLive do
        live "/", Categories, :index
        live "/:id/edit", Categories, :edit
        live "/new", Categories, :new
      end

      scope "/products", ProductLive do
        live "/", Products, :index
        live "/bulk", Bulk, :index
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
