defmodule DelivestWeb.Staff.AuthLive.Login do
  use DelivestWeb, :live_view
  alias Delivest.Identity

  defmodule LoginForm do
    use Ecto.Schema
    import Ecto.Changeset
    use Gettext, backend: DelivestWeb.Gettext

    @type t :: %__MODULE__{}

    @primary_key false
    embedded_schema do
      field :login, :string
      field :password, :string
    end

    def changeset(data \\ %__MODULE__{}, attrs) do
      data
      |> cast(attrs, [:login, :password])
      |> validate_required([:login, :password], message: dgettext_noop("errors", "is required"))
      |> validate_format(:login, Identity.login_regex(),
        message: dgettext_noop("errors", "should be a login")
      )
      |> validate_format(:password, Identity.password_regex(),
        message:
          dgettext_noop(
            "errors",
            "must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character"
          )
      )
    end
  end

  def mount(_params, _session, socket) do
    if socket.assigns[:current_user] do
      {:ok, redirect(socket, to: "/dashboard")}
    else
      changeset = LoginForm.changeset(%{})

      {:ok,
       assign(socket,
         form: to_form(changeset, as: "user"),
         error_message: nil,
         trigger_action: false
       )}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %LoginForm{}
      |> LoginForm.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"), error_message: nil)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    changeset =
      %LoginForm{}
      |> LoginForm.changeset(params)
      |> Map.put(:action, :insert)

    if changeset.valid? do
      login = Ecto.Changeset.get_field(changeset, :login)

      case Identity.get_staff_by_login(login) do
        {:ok, _account} ->
          {:noreply, assign(socket, form: to_form(changeset, as: "user"), trigger_action: true)}

        {:error, :not_found} ->
          {:noreply,
           assign(socket,
             form: to_form(changeset, as: "user"),
             error_message: gettext("Invalid login or password")
           )}
      end
    else
      {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex-1 flex flex-col items-center justify-center p-4">
      <div class="card w-full max-w-md">
        <div class="card-body gap-4 p-6">
          <div class="text-center">
            <h2 class="text-2xl font-display font-bold uppercase">
              {gettext("Welcome to Delivest CRM")}
            </h2>
            <p class="text-base-content/60 text-sm">
              {gettext("Sign in to your account to continue")}
            </p>
          </div>

          <%= if @error_message do %>
            <div role="alert" class="alert alert-error ">
              <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
              <span>{@error_message}</span>
            </div>
          <% end %>
          <.form
            id="user"
            for={@form}
            action={~p"/staff/auth/log_in"}
            phx-change="validate"
            phx-submit="submit"
            phx-trigger-action={assigns[:trigger_action]}
            class="flex flex-col gap-2"
          >
            <.input
              field={@form[:login]}
              type="text"
              label={gettext("login")}
              placeholder={gettext("Enter your login")}
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              placeholder="••••••••"
            />
            <button class="btn btn-primary w-full mt-4 phx-submit-loading:opacity-70">
              {gettext("Log in")}
              <.icon name="hero-chevron-right" />
            </button>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
