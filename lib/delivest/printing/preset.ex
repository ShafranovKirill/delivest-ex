defmodule Delivest.Printing.Preset do
  use Ecto.Schema
  import Ecto.Changeset

  @kitchen ~w(number readiness items kitchen_comments)
  @customer ~w(logo number items prices contacts free_text qr)

  @primary_key false
  embedded_schema do
    field :blocks, {:array, :string}, default: []
    field :paper, Ecto.Enum, values: [:a4, :a5], default: :a4
    field :free_text, :string
    field :qr_url, :string
    field :qr_kind, Ecto.Enum, values: [:menu, :feedback], default: :menu
  end

  def kitchen_blocks, do: @kitchen
  def customer_blocks, do: @customer
  def default(:kitchen), do: %__MODULE__{blocks: @kitchen}
  def default(:customer), do: %__MODULE__{blocks: ~w(logo number items prices contacts)}

  def kitchen_changeset(preset, attrs) do
    preset
    |> cast(attrs, [:blocks])
    |> validate_blocks(@kitchen)
  end

  def customer_changeset(preset, attrs) do
    preset
    |> cast(attrs, [:blocks, :paper, :free_text, :qr_url, :qr_kind])
    |> validate_blocks(@customer)
    |> validate_length(:free_text, max: 1000)
    |> validate_length(:qr_url, max: 500)
    |> validate_qr_url()
    |> validate_change(:qr_url, fn :qr_url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        _ -> [qr_url: "must be an HTTPS URL"]
      end
    end)
  end

  defp validate_blocks(changeset, allowed) do
    changeset =
      validate_change(changeset, :blocks, fn :blocks, blocks ->
        if is_list(blocks) and length(blocks) == length(Enum.uniq(blocks)) and
             Enum.all?(blocks, &(&1 in allowed)),
           do: [],
           else: [blocks: "must contain unique allowed blocks"]
      end)

    if is_nil(get_field(changeset, :blocks)),
      do: add_error(changeset, :blocks, "must be a list"),
      else: changeset
  end

  defp validate_qr_url(changeset) do
    if "qr" in (get_field(changeset, :blocks) || []) and
         String.trim(get_field(changeset, :qr_url) || "") == "" do
      add_error(changeset, :qr_url, "is required when QR is shown")
    else
      changeset
    end
  end
end
