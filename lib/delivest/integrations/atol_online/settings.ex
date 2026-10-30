defmodule Delivest.Integrations.AtolOnline.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :login, :string
    field :password, :string, redact: true
    field :group_code, :string
    field :sandbox, :boolean, default: false
    field :callback_token, :string
  end

  def changeset(settings, attrs, required?) do
    changeset =
      settings
      |> cast(attrs, [:login, :password, :group_code, :sandbox], empty_values: [])
      |> keep_password(settings)
      |> put_token()

    if required?,
      do: validate_required(changeset, [:login, :password, :group_code]),
      else: changeset
  end

  defp keep_password(changeset, %{password: password}) when is_binary(password) do
    case get_change(changeset, :password) do
      value when value in [nil, ""] -> put_change(changeset, :password, password)
      _value -> changeset
    end
  end

  defp keep_password(changeset, _settings), do: changeset

  defp put_token(changeset) do
    if get_field(changeset, :callback_token),
      do: changeset,
      else:
        put_change(
          changeset,
          :callback_token,
          Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
        )
  end
end
