defmodule Delivest.Identity.Staff do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity.{Role, StaffBranch}
  alias Delivest.Identity.Branch

  use Gettext, backend: DelivestWeb.Gettext

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:login],
    sortable: [:login, :inserted_at],
    default_limit: 10,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "staff" do
    field :login, :string
    field :name, :string
    field :password_hash, :string

    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :branch_ids, {:array, :binary_id}, virtual: true

    belongs_to :role, Role

    many_to_many :branches, Branch,
      join_through: StaffBranch,
      on_replace: :delete

    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(staff, attrs) do
    staff
    |> cast(attrs, [
      :login,
      :password,
      :name,
      :role_id,
      :deleted_at,
      :branch_ids,
      :password_confirmation
    ])
    |> validate_required([:login, :role_id])
    |> validate_password_required()
    |> validate_confirmation(:password, message: dgettext("errors", "does not match password"))
    |> validate_length(:login, min: 3, max: 50)
    |> validate_format(:login, login_regex(),
      message:
        dgettext_noop(
          "errors",
          "can only contain letters, numbers, dots, dashes, and underscores"
        )
    )
    |> put_assoc(:branches, attrs[:branches] || [])
    |> validate_format(:password, password_regex(),
      message:
        dgettext_noop(
          "errors",
          "must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character"
        )
    )
    |> unique_constraint(:login, name: :staff__login__uk)
    |> foreign_key_constraint(:role_id,
      name: :staff__role_id__fk,
      message: dgettext_noop("errors", "does not exist")
    )
    |> foreign_key_constraint(:branch_id,
      name: :staff__branch_id__fk,
      message: dgettext_noop("errors", "does not exist")
    )
    |> hash_password()
  end

  def password_changeset(staff, attrs) do
    staff
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_format(:password, password_regex(),
      message:
        dgettext_noop(
          "errors",
          "must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character"
        )
    )
    |> hash_password()
  end

  defp validate_password_required(changeset) do
    if is_nil(changeset.data.id) do
      validate_required(changeset, [:password])
    else
      changeset
    end
  end

  @spec hash_password(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
    end
  end

  @doc "Regular expression for validating login format"
  def login_regex, do: ~r/^[a-zA-Z0-9_.-]+$/

  @doc "Regular expression for validating strong passwords"
  def password_regex, do: ~r/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[\W_]).{8,}$/
end
