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
  end

  scope "/", DelivestWeb do
    pipe_through :browser

    get "/locale/:locale", LocaleController, :set
    post "/auth/log_in", SessionController, :create
    delete "/auth/log_out", SessionController, :delete
    get "/", PageController, :home
  end

  scope "/", DelivestWeb.ClientWeb do
    pipe_through :browser

    live_session :client_session,
      on_mount: [{DelivestWeb.Hooks.StaffAuth, :default}] do
    end
  end

  scope "/staff", DelivestWeb.Staff do
    pipe_through :staff_browser

    live_session :staff_public,
      layout: {DelivestWeb.Layouts, :staff_app},
      on_mount: [{DelivestWeb.Hooks.StaffAuth, :default}] do
      scope "/auth" do
        pipe_through :browser
        live "/login", AuthLive.Login, :new
      end
    end

    live_session :staff_authenticated,
      layout: {DelivestWeb.Layouts, :staff_app},
      on_mount: [
        {DelivestWeb.Hooks.StaffAuth, :default},
        {DelivestWeb.Hooks.StaffAuth, :require_authenticated_staff}
      ] do
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", DelivestWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:delivest, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DelivestWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
