defmodule Delivest.Printing.Preset do
  use Ecto.Schema
  import Ecto.Changeset

  @kitchen ~w(number readiness items kitchen_comments date reference staff_name text)
  @customer ~w(logo number items prices contacts free_text qr date reference customer_name staff_name address note fulfillment persons text)
  @kitchen_default ~w(number readiness items kitchen_comments)
  @customer_default ~w(logo number items prices contacts)

  @primary_key false
  embedded_schema do
    field :blocks, {:array, :string}, default: []
    field :paper, Ecto.Enum, values: [:a4, :a5, :roll58, :roll80], default: :a4
    field :layout, :map
    field :free_text, :string
    field :qr_url, :string
    field :qr_kind, Ecto.Enum, values: [:menu, :review, :custom, :feedback], default: :menu
  end

  def kitchen_blocks, do: @kitchen
  def customer_blocks, do: @customer
  def default(:kitchen), do: %__MODULE__{blocks: @kitchen_default}
  def default(:customer), do: %__MODULE__{blocks: @customer_default}

  def default_layout(:kitchen), do: layout_for(@kitchen_default)
  def default_layout(:customer), do: layout_for(@customer_default)

  def layout_for(types) do
    %{
      "rows" =>
        Enum.map(types, &%{"columns" => [%{"width" => 12, "blocks" => [%{"type" => &1}]}]})
    }
  end

  def kitchen_changeset(preset, attrs) do
    preset
    |> cast(attrs, [:blocks, :paper, :layout, :free_text])
    |> validate_blocks(@kitchen)
    |> validate_layout(@kitchen)
    |> validate_length(:free_text, max: 1000)
  end

  def customer_changeset(preset, attrs) do
    preset
    |> cast(attrs, [:blocks, :paper, :layout, :free_text, :qr_url, :qr_kind])
    |> validate_blocks(@customer)
    |> validate_layout(@customer)
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

  defp validate_layout(changeset, allowed) do
    validate_change(changeset, :layout, fn :layout, layout ->
      if valid_layout?(layout, allowed),
        do: [],
        else: [layout: "has invalid rows, columns or blocks"]
    end)
  end

  defp valid_layout?(nil, _), do: true

  defp valid_layout?(%{"rows" => rows}, allowed) when is_list(rows) and length(rows) <= 50 do
    Enum.all?(rows, fn
      %{"columns" => columns} when is_list(columns) and length(columns) in 1..12 ->
        Enum.all?(columns, &valid_column?(&1, allowed)) and
          Enum.reduce(columns, 0, &(Map.get(&1, "width", 12) + &2)) <= 12

      _ ->
        false
    end)
  end

  defp valid_layout?(_, _), do: false

  defp valid_column?(%{"blocks" => blocks} = column, allowed)
       when is_list(blocks) and length(blocks) <= 30 do
    valid_width?(Map.get(column, "width", 12)) and Enum.all?(blocks, &valid_block?(&1, allowed))
  end

  defp valid_column?(_, _), do: false

  defp valid_block?(%{"type" => type} = block, allowed) do
    type in allowed and valid_width?(Map.get(block, "width", 12)) and
      Map.get(block, "align", "left") in ["left", "center", "right"] and
      valid_int?(Map.get(block, "font_size", 14), 8, 40) and
      valid_int?(Map.get(block, "qr_size", 35), 10, 100) and
      valid_int?(Map.get(block, "logo_width", 55), 10, 150) and
      (not Map.has_key?(block, "text") or
         (is_binary(block["text"]) and String.length(block["text"]) <= 1000))
  end

  defp valid_block?(_, _), do: false
  defp valid_width?(value), do: valid_int?(value, 1, 12)
  defp valid_int?(value, min, max), do: is_integer(value) and value >= min and value <= max

  defp validate_qr_url(changeset) do
    layout_qr? =
      case get_field(changeset, :layout) do
        %{"rows" => rows} when is_list(rows) ->
          Enum.any?(rows, fn
            %{"columns" => columns} when is_list(columns) ->
              Enum.any?(columns, fn
                %{"blocks" => blocks} when is_list(blocks) ->
                  Enum.any?(blocks, &match?(%{"type" => "qr"}, &1))

                _ ->
                  false
              end)

            _ ->
              false
          end)

        _ ->
          false
      end

    qr? =
      if get_field(changeset, :layout),
        do: layout_qr?,
        else: "qr" in (get_field(changeset, :blocks) || [])

    if qr? and
         get_field(changeset, :qr_kind) in [:custom, :review, :feedback] and
         String.trim(get_field(changeset, :qr_url) || "") == "" do
      add_error(changeset, :qr_url, "is required when QR is shown")
    else
      changeset
    end
  end
end
