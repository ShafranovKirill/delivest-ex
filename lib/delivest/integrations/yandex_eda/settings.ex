defmodule Delivest.Integrations.YandexEda.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "yandex_eda_settings" do
    field :client_id, :string
    field :client_secret, :string, redact: true
    field :partner_name, :string
    field :push_client_id, :string
    field :push_client_secret, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:partner_name, :push_client_id, :push_client_secret], empty_values: [nil, ""])
    |> put_credentials()
  end

  def rotate(settings), do: change(settings, client_id: token(12), client_secret: token(32))

  def credentials?(%__MODULE__{client_id: id, client_secret: secret}),
    do: id not in [nil, ""] and secret not in [nil, ""]

  defp put_credentials(changeset) do
    if get_field(changeset, :client_id),
      do: changeset,
      else: change(changeset, client_id: token(12), client_secret: token(32))
  end

  defp token(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
