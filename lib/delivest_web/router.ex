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
    get "/", PageController, :home
  end

  scope "/", DelivestWeb.Client do
    pipe_through :browser

    live_session :client_public,
      on_mount: [] do
    end
  end

  scope "/staff", DelivestWeb.Staff do
    pipe_through :staff_browser

    post "/auth/log_in", StaffSessionController, :create
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
        {DelivestWeb.Hooks.StaffAuth, :require_authenticated_staff}
      ] do
      live "/branches/select", BranchLive.BranchSelect, :index

      scope "/branches", BranchLive do
        live "/", Branches, :index
        live "/:slug/edit", Branches, :edit
        live "/new", Branches, :new
      end

      scope "/employee", StaffLive do
        live "/", Staffs, :index
        live "/:id/edit", Staffs, :edit
        live "/new", Staffs, :new
      end

      scope "/roles", RoleLive do
        live "/", Roles, :index
        live "/:id/edit", Roles, :edit
        live "/new", Roles, :new
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

      scope "/categories", CategoryLive do
        live "/", Categories, :index
        live "/:id/edit", Categories, :edit
        live "/new", Categories, :new
      end

      scope "/products", ProductLive do
        live "/", Products, :index
        live "/:id/edit", Products, :edit
        live "/new", Products, :new
      end
    end
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
