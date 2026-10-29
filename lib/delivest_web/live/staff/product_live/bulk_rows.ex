defmodule DelivestWeb.Staff.ProductLive.BulkRows do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Net.Product

  @columns ~w(name price weight quantity category external_id description)
  @max_rows 300

  @aliases %{
    "name" => ~w(название наименование товар блюдо name title),
    "price" => ~w(цена стоимость price),
    "weight" => ~w(вес граммы weight),
    "quantity" => ["кол-во", "количество", "штук", "quantity", "qty"],
    "category" => ~w(категория раздел category),
    "external_id" => ["crm id", "id crm", "crm", "артикул", "код", "external_id", "external id"],
    "description" => ~w(описание состав description)
  }

  def columns, do: @columns
  def max_rows, do: @max_rows

  def label("name"), do: gettext("Name")
  def label("price"), do: gettext("Price")
  def label("weight"), do: gettext("Weight, g")
  def label("quantity"), do: gettext("Pieces")
  def label("category"), do: gettext("Category")
  def label("external_id"), do: gettext("CRM ID")
  def label("description"), do: gettext("Description")

  def required?(column), do: column in ~w(name price)

  def blank_values, do: Map.new(@columns, &{&1, ""})

  def blank?(values), do: Enum.all?(@columns, &(String.trim(values[&1] || "") == ""))

  def paste(text, start_column) do
    lines =
      text
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.split("\n")
      |> Enum.map(&String.split(&1, "\t"))
      |> Enum.reject(&Enum.all?(&1, fn cell -> String.trim(cell) == "" end))

    case lines do
      [header | rest] ->
        case header_columns(header) do
          nil -> Enum.map(lines, &positional(&1, start_column))
          columns -> Enum.map(rest, &by_header(&1, columns))
        end

      [] ->
        []
    end
  end

  def validate(values) do
    {attrs, errors} =
      Enum.reduce(@columns, {%{}, %{}}, fn column, {attrs, errors} ->
        case parse(column, String.trim(values[column] || "")) do
          {:ok, nil} -> {attrs, errors}
          {:ok, value} -> {Map.put(attrs, column, value), errors}
          {:error, message} -> {attrs, Map.put(errors, column, message)}
        end
      end)

    changeset = Product.changeset(%Product{}, Map.drop(attrs, ["category"]))

    errors =
      Enum.reduce(changeset.errors, errors, fn {field, {message, opts}}, acc ->
        Map.put_new(
          acc,
          to_string(field),
          DelivestWeb.CoreComponents.translate_error({message, opts})
        )
      end)

    {Map.put(attrs, "is_active", true), errors}
  end

  defp parse(column, "") when column in ~w(name price), do: {:error, gettext("Required")}
  defp parse(_column, ""), do: {:ok, nil}

  defp parse("price", value) do
    case money(value) do
      nil -> {:error, gettext("Not a price")}
      amount -> {:ok, Delivest.Money.from_rubles(amount)}
    end
  end

  defp parse(column, value) when column in ~w(weight quantity) do
    case money(value) do
      nil -> {:error, gettext("Not a number")}
      number -> {:ok, round(number)}
    end
  end

  defp parse(_column, value), do: {:ok, value}

  defp money(value) do
    cleaned =
      value
      |> String.replace(~r/[\s\x{00A0}\x{202F}]/u, "")
      |> String.replace(~r/(₽|руб\.?|р\.|rub|г|гр|шт)$/iu, "")
      |> String.replace(",", ".")

    case Float.parse(cleaned) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp header_columns(cells) do
    columns = Enum.map(cells, &header_column/1)
    if Enum.count(columns, & &1) >= 2, do: columns
  end

  defp header_column(cell) do
    normalized =
      cell
      |> String.downcase()
      |> String.replace(~r/[*:(),.]/u, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    find_alias(&(&1 == normalized)) ||
      find_alias(&String.starts_with?(normalized, &1 <> " "))
  end

  defp find_alias(match?) do
    Enum.find_value(@aliases, fn {column, names} -> if Enum.any?(names, match?), do: column end)
  end

  defp by_header(cells, columns) do
    columns
    |> Enum.zip(cells)
    |> Enum.reduce(%{}, fn
      {nil, _cell}, acc -> acc
      {column, cell}, acc -> Map.put(acc, column, String.trim(cell))
    end)
  end

  defp positional(cells, start_column) do
    @columns
    |> Enum.drop(Enum.find_index(@columns, &(&1 == start_column)) || 0)
    |> Enum.zip(cells)
    |> Map.new(fn {column, cell} -> {column, String.trim(cell)} end)
  end
end
