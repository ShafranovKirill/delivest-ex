defmodule Delivest.Net.ProductWorkbook do
  @moduledoc "Version 1 product workbook. Values use local IDs and rubles with exact kopecks."
  import Bitwise, only: [band: 2]

  @schema_version "delivest-products-v1"
  @headers ~w(schema_version source_key name price_rub old_price_rub description quantity weight measure_unit is_active calories proteins fats carbohydrates excise vat tags suggested stars_price stars_reward category_id modifier_group_ids media_id)
  @max_zip 5 * 1024 * 1024
  @max_xml 20 * 1024 * 1024
  @max_cell 32 * 1024
  def headers, do: @headers

  def limits,
    do: %{
      compressed: @max_zip,
      uncompressed: @max_xml,
      entries: 40,
      rows: 1000,
      columns: 40,
      cell: @max_cell
    }

  def encode(rows) when is_list(rows) and length(rows) <= 1000 do
    if Enum.all?(rows, &valid_encode_row?/1),
      do: do_encode(rows),
      else: {:error, :invalid_cell}
  end

  def encode(_), do: {:error, :too_many_rows}

  defp valid_encode_row?(row) when is_map(row) do
    Enum.all?(@headers, fn key ->
      value = Map.get(row, key)
      text = if is_list(value), do: Enum.join(value, ","), else: to_string(value || "")

      String.valid?(text) and byte_size(text) <= @max_cell and
        not Regex.match?(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, text)
    end)
  end

  defp valid_encode_row?(_), do: false

  defp do_encode(rows) do
    sheet_rows = [
      @headers
      | Enum.map(rows, fn row ->
          Enum.map(@headers, fn key ->
            if key == "schema_version", do: @schema_version, else: Map.get(row, key)
          end)
        end)
    ]

    sheet =
      ~s|<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>| <>
        (sheet_rows
         |> Enum.with_index(1)
         |> Enum.map_join("", fn {cells, i} ->
           "<row r=\"#{i}\">" <>
             (cells
              |> Enum.with_index(1)
              |> Enum.map_join("", fn {value, col} ->
                ref = column(col) <> Integer.to_string(i)
                "<c r=\"#{ref}\" t=\"inlineStr\"><is><t>#{escape(value)}</t></is></c>"
              end)) <> "</row>"
         end)) <> "</sheetData></worksheet>"

    files = [
      {~c"[Content_Types].xml",
       "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"},
      {~c"_rels/.rels",
       "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"},
      {~c"xl/workbook.xml",
       "<?xml version=\"1.0\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Products\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"},
      {~c"xl/_rels/workbook.xml.rels",
       "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"},
      {~c"xl/worksheets/sheet1.xml", sheet}
    ]

    if byte_size(sheet) > @max_xml do
      {:error, :workbook_too_large}
    else
      case :zip.create(~c"products.xlsx", files, [:memory]) do
        {:ok, {_name, binary}} when byte_size(binary) <= @max_zip -> {:ok, binary}
        {:ok, _} -> {:error, :workbook_too_large}
        _ -> {:error, :invalid_workbook}
      end
    end
  end

  def decode(binary) when is_binary(binary) and byte_size(binary) <= @max_zip do
    with {:ok, listing} <- :zip.list_dir(binary),
         :ok <- validate_listing(listing, binary),
         {:ok, entries} <- :zip.extract(binary, [:memory]),
         files = Map.new(entries, fn {name, body} -> {List.to_string(name), body} end),
         :ok <- validate_xml(files),
         {:ok, sheet_path} <- product_sheet_path(files),
         {:ok, shared} <- shared_strings(files),
         {:ok, rows} <- parse_sheet(files[sheet_path], shared),
         {:ok, records} <- validate_rows(rows) do
      {:ok, records}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :invalid_workbook}
  catch
    _, _ -> {:error, :invalid_workbook}
  end

  def decode(_), do: {:error, :file_too_large}

  defp validate_listing(entries, binary) do
    files = Enum.filter(entries, &(elem(&1, 0) == :zip_file))
    names = Enum.map(files, &List.to_string(elem(&1, 1)))
    total = Enum.reduce(files, 0, fn file, acc -> acc + elem(elem(file, 2), 1) end)

    allowed = fn name ->
      name in [
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/sharedStrings.xml",
        "xl/styles.xml",
        "xl/theme/theme1.xml",
        "docProps/app.xml",
        "docProps/core.xml"
      ] or
        Regex.match?(~r/^xl\/worksheets\/sheet[0-9]+\.xml$/, name)
    end

    cond do
      length(files) > 40 or total > @max_xml ->
        {:error, :workbook_too_large}

      length(names) != length(Enum.uniq(names)) or not Enum.all?(names, allowed) or
          not regular_zip_entries?(binary, length(files)) ->
        {:error, :invalid_archive_entries}

      not Enum.all?(["xl/workbook.xml", "xl/_rels/workbook.xml.rels"], &(&1 in names)) ->
        {:error, :invalid_workbook}

      true ->
        :ok
    end
  end

  defp regular_zip_entries?(archive, count) when byte_size(archive) >= 22 do
    end_offset = byte_size(archive) - 22

    case binary_part(archive, end_offset, 22) do
      <<0x06054B50::little-32, 0::32, ^count::little-16, ^count::little-16, size::little-32,
        offset::little-32, 0::16>>
      when offset + size == end_offset ->
        archive |> binary_part(offset, size) |> regular_zip_directory?(count)

      _ ->
        false
    end
  end

  defp regular_zip_entries?(_, _), do: false
  defp regular_zip_directory?(<<>>, 0), do: true

  defp regular_zip_directory?(
         <<0x02014B50::little-32, _version_made::little-16, _version_needed::little-16,
           flags::little-16, method::little-16, _time::little-16, _date::little-16,
           _crc::little-32, _compressed::little-32, _uncompressed::little-32,
           name_size::little-16, extra_size::little-16, comment_size::little-16, 0::little-16,
           _internal::little-16, attributes::little-32, _offset::little-32, rest::binary>>,
         count
       )
       when count > 0 and band(flags, 1) == 0 and method in [0, 8] and
              div(attributes, 0x10000000) in [0, 8] do
    skip = name_size + extra_size + comment_size

    case rest do
      <<_::binary-size(skip), tail::binary>> -> regular_zip_directory?(tail, count - 1)
      _ -> false
    end
  end

  defp regular_zip_directory?(_, _), do: false

  defp validate_xml(files) do
    if Enum.all?(files, fn {name, body} ->
         if String.ends_with?(name, ".xml") or String.ends_with?(name, ".rels") do
           utf8_xml?(body) and
             not Regex.match?(~r/<!\s*(?:DOCTYPE|ENTITY)\b/i, body) and
             not Regex.match?(~r/<(?:[A-Za-z0-9_]+:)?f(?:\s|>)/i, body) and
             not Regex.match?(~r/<(?:[A-Za-z0-9_]+:)?hyperlink(?:\s|>)/i, body)
         else
           true
         end
       end), do: :ok, else: {:error, :unsafe_xml}
  end

  defp utf8_xml?(body) do
    encoding = Regex.run(~r/<\?xml[^>]*encoding\s*=\s*['"]([^'"]+)['"]/i, body)
    declared = if encoding, do: encoding |> Enum.at(1) |> String.upcase(), else: "UTF-8"

    String.valid?(body) and not String.contains?(body, <<0>>) and
      not String.starts_with?(body, [
        <<0xFF, 0xFE>>,
        <<0xFE, 0xFF>>,
        <<0, 0, 0xFE, 0xFF>>,
        <<0xFF, 0xFE, 0, 0>>
      ]) and
      declared in ["UTF-8", "US-ASCII"]
  end

  defp product_sheet_path(files) do
    {:ok, workbook} = parse_xml(files["xl/workbook.xml"])
    sheets = :xmerl_xpath.string(~c"//*[local-name()='sheets']/*[local-name()='sheet']", workbook)
    products = Enum.filter(sheets, &(attr(&1, "name") == "Products"))
    {:ok, rels} = parse_xml(files["xl/_rels/workbook.xml.rels"])
    relationships = :xmerl_xpath.string(~c"//*[local-name()='Relationship']", rels)

    all_rels =
      Enum.flat_map(files, fn {name, xml} ->
        if String.ends_with?(name, ".rels") do
          {:ok, document} = parse_xml(xml)
          :xmerl_xpath.string(~c"//*[local-name()='Relationship']", document)
        else
          []
        end
      end)

    external? = Enum.any?(all_rels, &(String.downcase(attr(&1, "TargetMode")) == "external"))

    case products do
      [sheet] when not external? ->
        id = attr(sheet, "r:id")
        relation = Enum.find(relationships, &(attr(&1, "Id") == id))
        target = relation && attr(relation, "Target")
        path = if target, do: "xl/" <> String.trim_leading(target, "/xl/"), else: ""

        if Regex.match?(~r/^xl\/worksheets\/sheet[0-9]+\.xml$/, path) and
             Map.has_key?(files, path), do: {:ok, path}, else: {:error, :invalid_relationships}

      _ ->
        {:error, :invalid_relationships}
    end
  end

  defp shared_strings(files) do
    case files["xl/sharedStrings.xml"] do
      nil ->
        {:ok, []}

      xml ->
        {:ok, doc} = parse_xml(xml)
        {:ok, :xmerl_xpath.string(~c"//*[local-name()='si']", doc) |> Enum.map(&node_text/1)}
    end
  end

  defp parse_sheet(xml, shared) do
    {:ok, doc} = parse_xml(xml)
    rows = :xmerl_xpath.string(~c"//*[local-name()='sheetData']/*[local-name()='row']", doc)

    if length(rows) > 1001,
      do: {:error, :too_many_rows},
      else: {:ok, Enum.map(rows, &parse_row(&1, shared))}
  end

  defp parse_row(row, shared) do
    cells = :xmerl_xpath.string(~c"./*[local-name()='c']", row)
    if length(cells) > 40, do: throw(:too_many_columns)

    refs = Enum.map(cells, &attr(&1, "r"))
    if length(refs) != length(Enum.uniq(refs)), do: throw(:duplicate_cells)

    Map.new(cells, fn cell ->
      ref = attr(cell, "r")
      col = ref |> String.replace(~r/\d+$/, "") |> column_number()
      type = attr(cell, "t")

      value =
        case type do
          "s" ->
            shared |> Enum.at(String.to_integer(node_text(cell))) || throw(:invalid_shared_string)

          "b" ->
            case node_text(cell) do
              "1" -> "true"
              "0" -> "false"
              _ -> throw(:invalid_boolean)
            end

          value when value in ["", "n", "inlineStr", "str"] ->
            node_text(cell)

          _ ->
            throw(:invalid_cell_type)
        end

      if byte_size(value) > @max_cell or col < 1 or col > length(@headers),
        do: throw(:invalid_cell)

      {col, value}
    end)
  end

  defp validate_rows([]), do: {:error, :missing_header}

  defp validate_rows([header | data]) do
    if Enum.map(1..length(@headers), &Map.get(header, &1, "")) != @headers or
         map_size(header) != length(@headers) do
      {:error, :invalid_header}
    else
      records =
        Enum.with_index(data, 2)
        |> Enum.map(fn {row, index} ->
          %{
            line: index,
            values:
              Map.new(Enum.with_index(@headers, 1), fn {key, col} ->
                {key, Map.get(row, col, "")}
              end)
          }
        end)

      keys = Enum.map(records, & &1.values["source_key"])
      versions = Enum.map(records, & &1.values["schema_version"])

      if Enum.any?(versions, &(&1 != @schema_version)) or
           Enum.any?(keys, &(&1 == "" or byte_size(&1) > 128)) or
           length(keys) != length(Enum.uniq(keys)),
         do: {:error, :invalid_source_keys},
         else: {:ok, records}
    end
  end

  defp parse_xml(xml) do
    {doc, _} =
      :xmerl_scan.string(:binary.bin_to_list(xml), [{:fetch_fun, fn _, _ -> {:ok, []} end}])

    {:ok, doc}
  end

  defp attr(node, name) do
    node
    |> elem(7)
    |> Enum.find_value("", fn attr ->
      if to_string(elem(attr, 1)) == name, do: to_string(elem(attr, 8))
    end)
  end

  defp node_text(node) do
    :xmerl_xpath.string(~c".//*[local-name()='t']/text() | ./*[local-name()='v']/text()", node)
    |> Enum.map_join("", fn item -> to_string(elem(item, 4)) end)
  end

  defp column(n) when n <= 26, do: <<64 + n>>
  defp column(n), do: <<64 + div(n - 1, 26), 65 + rem(n - 1, 26)>>

  defp column_number(text),
    do: text |> String.to_charlist() |> Enum.reduce(0, fn char, acc -> acc * 26 + char - 64 end)

  defp escape(nil), do: ""

  defp escape(value) do
    value = if is_list(value), do: Enum.join(value, ","), else: to_string(value)

    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
