defmodule Delivest.Net.ProductOperationsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory
  alias Delivest.{Net.ProductOperations, Net.ProductWorkbook, Relations}
  alias Delivest.Net.Product

  setup do
    source = insert(:branch)
    target = insert(:branch)
    staff = insert(:staff, role: insert(:role, permissions: ["admin"]))
    %{source: source, target: target, staff: staff}
  end

  test "workbook round trips declared fields and rejects duplicate keys" do
    row = Map.new(ProductWorkbook.headers(), &{&1, ""})

    row =
      Map.merge(row, %{
        "source_key" => "sku-1",
        "name" => "Чай & кофе",
        "price_rub" => "12,35",
        "is_active" => "true",
        "measure_unit" => "g",
        "suggested" => "false",
        "tags" => ~s(["чай,кофе","суп"])
      })

    assert {:ok, binary} = ProductWorkbook.encode([row])
    assert {:ok, [%{values: decoded}]} = ProductWorkbook.decode(binary)
    assert decoded == Map.put(row, "schema_version", "delivest-products-v1")
    assert {:ok, duplicate} = ProductWorkbook.encode([row, row])
    assert {:error, :invalid_source_keys} = ProductWorkbook.decode(duplicate)
  end

  test "reads Excel shared strings, boolean cells and styles" do
    row =
      Map.new(ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{
        "source_key" => "sku-excel",
        "name" => "Tea",
        "price_rub" => "2",
        "measure_unit" => "g",
        "is_active" => "true",
        "suggested" => "false"
      })

    {:ok, binary} = ProductWorkbook.encode([row])

    changed =
      rewrite_zip(
        binary,
        fn
          "xl/worksheets/sheet1.xml", body ->
            body
            |> String.replace(
              ~s(<c r="C2" t="inlineStr"><is><t>Tea</t></is></c>),
              ~s(<c r="C2" t="s"><v>0</v></c>)
            )
            |> String.replace(
              ~s(<c r="J2" t="inlineStr"><is><t>true</t></is></c>),
              ~s(<c r="J2" t="b"><v>1</v></c>)
            )

          _, body ->
            body
        end,
        [
          {~c"xl/sharedStrings.xml",
           ~s(<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Tea</t></si></sst>)},
          {~c"xl/styles.xml",
           ~s(<?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font/></fonts><fills count="1"><fill/></fills></styleSheet>)}
        ]
      )

    assert {:ok, [%{values: %{"name" => "Tea", "is_active" => "true"}}]} =
             ProductWorkbook.decode(changed)
  end

  test "rejects formulas, DTD and external relationships" do
    row =
      Map.new(ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{"source_key" => "sku", "name" => "Tea"})

    {:ok, binary} = ProductWorkbook.encode([row])

    formula =
      rewrite_zip(binary, fn
        "xl/worksheets/sheet1.xml", body ->
          String.replace(body, "</sheetData>", ~s(<f>1+1</f></sheetData>))

        _, body ->
          body
      end)

    assert {:error, :unsafe_xml} = ProductWorkbook.decode(formula)

    dtd =
      rewrite_zip(binary, fn
        "xl/workbook.xml", body ->
          String.replace(body, "<workbook", "<!DOCTYPE workbook><workbook")

        _, body ->
          body
      end)

    assert {:error, :unsafe_xml} = ProductWorkbook.decode(dtd)

    external =
      rewrite_zip(binary, fn
        "xl/_rels/workbook.xml.rels", body ->
          String.replace(body, "Target=", ~s(TargetMode = "External" Target=))

        _, body ->
          body
      end)

    assert {:error, :invalid_relationships} = ProductWorkbook.decode(external)
  end

  test "rejects invalid header, duplicate cells, UTF-16 and row limit" do
    row =
      Map.new(ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{"source_key" => "sku", "name" => "Tea"})

    {:ok, binary} = ProductWorkbook.encode([row])

    wrong_header =
      rewrite_zip(binary, fn
        "xl/worksheets/sheet1.xml", body ->
          String.replace(body, ">schema_version<", ">unknown_field<")

        _, body ->
          body
      end)

    assert {:error, :invalid_header} = ProductWorkbook.decode(wrong_header)

    duplicate_cell =
      rewrite_zip(binary, fn
        "xl/worksheets/sheet1.xml", body ->
          String.replace(
            body,
            "</row><row r=\"2\">",
            "<c r=\"A1\" t=\"inlineStr\"><is><t>extra</t></is></c></row><row r=\"2\">"
          )

        _, body ->
          body
      end)

    assert {:error, :invalid_workbook} = ProductWorkbook.decode(duplicate_cell)

    utf16 =
      rewrite_zip(binary, fn
        "xl/workbook.xml", body -> <<0xFF, 0xFE>> <> body
        _, body -> body
      end)

    assert {:error, :unsafe_xml} = ProductWorkbook.decode(utf16)
    assert {:error, :too_many_rows} = ProductWorkbook.encode(List.duplicate(row, 1001))
  end

  defp rewrite_zip(binary, transform, additions \\ []) do
    {:ok, entries} = :zip.extract(binary, [:memory])

    files =
      Enum.map(entries, fn {name, body} -> {name, transform.(List.to_string(name), body)} end) ++
        additions

    {:ok, {_, rewritten}} = :zip.create(~c"products.xlsx", files, [:memory])
    rewritten
  end

  test "copy is idempotent, preserves source and excludes CRM IDs", ctx do
    source = insert_branch_product(ctx.source.id, name: "Copy me", price: 125)
    assert {:ok, 1} = ProductOperations.copy(ctx.staff, :all, ctx.source.id, ctx.target.id)
    assert {:ok, 0} = ProductOperations.copy(ctx.staff, :all, ctx.source.id, ctx.target.id)
    assert [target_id] = Relations.list_target_ids("Branch", ctx.target.id, "Product")
    assert target_id != source.id
    assert Relations.related?("Branch", ctx.source.id, "Product", source.id)
    assert Repo.preload(Repo.get!(Product, target_id), :external_ids).external_ids == []
  end

  test "import preview offers per-row skip or update and repeat skips", ctx do
    row = Map.new(ProductWorkbook.headers(), &{&1, ""})

    row =
      Map.merge(row, %{
        "source_key" => "sku-1",
        "name" => "New",
        "price_rub" => "1,25",
        "is_active" => "true",
        "measure_unit" => "g",
        "suggested" => "false"
      })

    {:ok, workbook} = ProductWorkbook.encode([row])
    assert {:ok, preview} = ProductOperations.import_preview(ctx.staff, ctx.target.id, workbook)
    assert preview.counts == %{new: 1}
    assert {:ok, %{created: 1}} = ProductOperations.apply_changes(ctx.staff, preview)
    assert {:ok, repeat} = ProductOperations.import_preview(ctx.staff, ctx.target.id, workbook)
    assert repeat.counts == %{match: 1}
    assert {:ok, %{skipped: 1}} = ProductOperations.apply_changes(ctx.staff, repeat)
    assert length(Relations.list_target_ids("Branch", ctx.target.id, "Product")) == 1

    assert {:ok, %{updated: 1}} =
             ProductOperations.apply_changes(ctx.staff, repeat, %{"sku-1" => "update"})
  end

  test "preview becomes stale after another import", ctx do
    row =
      Map.new(ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{
        "source_key" => "sku-stale",
        "name" => "New",
        "price_rub" => "1",
        "is_active" => "true",
        "measure_unit" => "g",
        "suggested" => "false"
      })

    {:ok, workbook} = ProductWorkbook.encode([row])
    {:ok, preview} = ProductOperations.import_preview(ctx.staff, ctx.target.id, workbook)
    assert {:ok, _} = ProductOperations.apply_changes(ctx.staff, preview)
    assert {:error, :stale_preview} = ProductOperations.apply_changes(ctx.staff, preview)
  end

  test "matched target edit invalidates preview even within the same second", ctx do
    source = insert_branch_product(ctx.source.id, name: "Tea")
    assert {:ok, 1} = ProductOperations.copy(ctx.staff, [source.id], ctx.source.id, ctx.target.id)

    assert {:ok, preview} =
             ProductOperations.copy_preview(ctx.staff, [source.id], ctx.source.id, ctx.target.id)

    [target_id] = Relations.list_target_ids("Branch", ctx.target.id, "Product")
    Repo.get!(Product, target_id) |> Ecto.Changeset.change(price: 321) |> Repo.update!()

    assert {:error, :stale_preview} =
             ProductOperations.apply_changes(ctx.staff, preview, %{source.id => "update"})
  end

  test "copied target workbook imports back into its own branch", ctx do
    source = insert_branch_product(ctx.source.id, name: "Tea")
    assert {:ok, 1} = ProductOperations.copy(ctx.staff, [source.id], ctx.source.id, ctx.target.id)
    {:ok, book} = ProductOperations.export(ctx.staff, ctx.target.id)
    {:ok, [%{values: values}]} = ProductWorkbook.decode(book)
    assert values["source_key"] != source.id
    {:ok, preview} = ProductOperations.import_preview(ctx.staff, ctx.target.id, book)
    assert preview.counts == %{match: 1}

    assert {:ok, %{updated: 1}} =
             ProductOperations.apply_changes(ctx.staff, preview, %{
               values["source_key"] => "update"
             })

    {:ok, repeat} = ProductOperations.import_preview(ctx.staff, ctx.target.id, book)
    assert {:ok, %{skipped: 1}} = ProductOperations.apply_changes(ctx.staff, repeat)
    assert length(Relations.list_target_ids("Branch", ctx.target.id, "Product")) == 1
  end

  test "exported UUID of a soft-deleted target is rejected before apply", ctx do
    target = insert_branch_product(ctx.target.id, name: "Removed tea")
    assert {:ok, workbook} = ProductOperations.export(ctx.staff, ctx.target.id)
    assert {:ok, _} = Delivest.Net.Products.soft_delete_product(ctx.staff, target)
    assert Relations.related?("Branch", ctx.target.id, "Product", target.id)

    assert {:ok, preview} = ProductOperations.import_preview(ctx.staff, ctx.target.id, workbook)
    assert [%{status: :error, errors: [:deleted_target]}] = preview.rows

    assert {:error, {:row, 2, [:deleted_target]}} =
             ProductOperations.apply_changes(ctx.staff, preview)

    assert Repo.get!(Product, target.id).deleted_at != nil
    assert Relations.list_target_ids("Branch", ctx.target.id, "Product") == [target.id]
  end

  test "modifier references require target product read permission", ctx do
    group =
      %Delivest.Net.ModifierGroup{}
      |> Delivest.Net.ModifierGroup.changeset(%{name: "Sugar", min: 0, max: 1})
      |> Repo.insert!()

    row =
      Map.new(ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{
        "source_key" => "sku-mod",
        "name" => "Tea",
        "price_rub" => "1",
        "measure_unit" => "g",
        "is_active" => "true",
        "suggested" => "false",
        "modifier_group_ids" => group.id
      })

    {:ok, book} = ProductWorkbook.encode([row])
    creator = insert(:staff, role: insert(:role, permissions: ["products.create"]))
    insert(:staff_branch, staff: creator, branch: ctx.target)
    assert {:ok, preview} = ProductOperations.import_preview(creator, ctx.target.id, book)
    assert [%{status: :error, errors: [:forbidden_modifier_reference]}] = preview.rows
  end

  test "changed apply writes one audit event and skipped repeat writes none", ctx do
    source = insert_branch_product(ctx.source.id, name: "Tea")

    {:ok, preview} =
      ProductOperations.copy_preview(ctx.staff, [source.id], ctx.source.id, ctx.target.id)

    assert {:ok, %{created: 1}} = ProductOperations.apply_changes(ctx.staff, preview)

    assert [event] =
             Repo.all(
               from e in Delivest.Audit.Event,
                 where: e.action == "product.bulk_applied" and e.branch_id == ^ctx.target.id
             )

    assert event.metadata["created"] == 1
    assert event.metadata["source_branch_id"] == ctx.source.id

    {:ok, repeat} =
      ProductOperations.copy_preview(ctx.staff, [source.id], ctx.source.id, ctx.target.id)

    assert {:ok, %{skipped: 1}} = ProductOperations.apply_changes(ctx.staff, repeat)

    assert Repo.aggregate(
             from(e in Delivest.Audit.Event,
               where: e.action == "product.bulk_applied" and e.branch_id == ^ctx.target.id
             ),
             :count
           ) == 1
  end

  test "foreign branch and unauthorized staff cannot preview copy", ctx do
    foreign = insert(:branch)
    foreign_product = insert_branch_product(foreign.id, name: "Foreign")

    assert {:ok, preview} =
             ProductOperations.copy_preview(
               ctx.staff,
               [foreign_product.id],
               ctx.source.id,
               ctx.target.id
             )

    assert preview.rows == []
    reader = insert(:staff, role: insert(:role, permissions: ["products.read"]))
    insert(:staff_branch, staff: reader, branch: ctx.source)

    assert {:error, :forbidden} =
             ProductOperations.copy_preview(reader, :all, ctx.source.id, ctx.target.id)
  end

  test "copy preserves category, global modifier link and permitted public photo", ctx do
    {:ok, category} =
      Delivest.Net.Categories.create_category(ctx.staff, ctx.source.id, %{
        "name" => "Drinks",
        "is_active" => true
      })

    group =
      %Delivest.Net.ModifierGroup{}
      |> Delivest.Net.ModifierGroup.changeset(%{name: "Sugar", min: 0, max: 1})
      |> Repo.insert!()

    file =
      %Delivest.Media.File{}
      |> Delivest.Media.File.changeset(%{
        bucket: "products",
        key: "test/tea",
        original_name: "tea.png",
        mime_type: "image/png",
        size: 10,
        context: :product,
        owner_id: ctx.staff.id
      })
      |> Repo.insert!()

    source =
      insert_branch_product(ctx.source.id,
        name: "Tea",
        price: 135,
        category_id: category.id,
        media_id: file.id,
        tags: ["hot, sweet"]
      )

    assert {:ok, _} = Delivest.Net.Modifiers.attach(ctx.staff, source.id, [group.id])
    assert {:ok, workbook} = ProductOperations.export(ctx.staff, ctx.source.id)
    assert {:ok, [%{values: values}]} = ProductWorkbook.decode(workbook)
    assert values["category_id"] == category.id
    assert values["modifier_group_ids"] == group.id
    assert values["media_id"] == file.id
    assert values["tags"] == ~s(["hot, sweet"])
    assert {:ok, preview} = ProductOperations.import_preview(ctx.staff, ctx.target.id, workbook)
    assert preview.counts == %{new: 1}
    assert {:ok, %{created: 1}} = ProductOperations.apply_changes(ctx.staff, preview)
    [target_id] = Relations.list_target_ids("Branch", ctx.target.id, "Product")
    target = Repo.get!(Product, target_id)
    assert target.category_id != category.id
    assert target.media_id == file.id
    assert target.tags == ["hot, sweet"]
    assert Delivest.Net.Modifiers.group_ids(target.id) == [group.id]
    assert Relations.related?("Branch", ctx.target.id, "Category", target.category_id)
  end

  test "shared matched target can be skipped but cannot be updated", ctx do
    source = insert_branch_product(ctx.source.id, name: "Shared source")
    assert {:ok, 1} = ProductOperations.copy(ctx.staff, :all, ctx.source.id, ctx.target.id)
    [target_id] = Relations.list_target_ids("Branch", ctx.target.id, "Product")
    third = insert(:branch)
    assert {:ok, _} = Relations.create_relation(Repo, "Branch", third.id, "Product", target_id)

    assert {:ok, preview} =
             ProductOperations.copy_preview(ctx.staff, [source.id], ctx.source.id, ctx.target.id)

    assert [%{status: :match, update_allowed: false}] = preview.rows
    assert {:ok, %{skipped: 1}} = ProductOperations.apply_changes(ctx.staff, preview)

    assert {:error, {:row, 1, :shared_or_forbidden_target}} =
             ProductOperations.apply_changes(ctx.staff, preview, %{source.id => "update"})
  end

  test "create-only staff can skip matched rows", ctx do
    insert_branch_product(ctx.source.id, name: "Tea")
    assert {:ok, 1} = ProductOperations.copy(ctx.staff, :all, ctx.source.id, ctx.target.id)
    staff = insert(:staff, role: insert(:role, permissions: ["products.read", "products.create"]))
    insert(:staff_branch, staff: staff, branch: ctx.source)
    insert(:staff_branch, staff: staff, branch: ctx.target)

    assert {:ok, preview} =
             ProductOperations.copy_preview(staff, :all, ctx.source.id, ctx.target.id)

    assert [%{status: :match, update_allowed: false}] = preview.rows
    assert {:ok, %{skipped: 1}} = ProductOperations.apply_changes(staff, preview)
  end

  test "category creation permission is checked in preview", ctx do
    {:ok, category} =
      Delivest.Net.Categories.create_category(ctx.staff, ctx.source.id, %{"name" => "Tea"})

    insert_branch_product(ctx.source.id, name: "Tea", category_id: category.id)

    staff =
      insert(:staff,
        role: insert(:role, permissions: ["products.read", "products.create", "categories.read"])
      )

    insert(:staff_branch, staff: staff, branch: ctx.source)
    insert(:staff_branch, staff: staff, branch: ctx.target)

    assert {:ok, preview} =
             ProductOperations.copy_preview(staff, :all, ctx.source.id, ctx.target.id)

    assert [%{status: :error, errors: [:forbidden_category]}] = preview.rows
  end

  test "row failure rolls back earlier writes", ctx do
    row =
      Map.new(ProductWorkbook.headers(), &{&1, ""})
      |> Map.merge(%{
        "source_key" => "sku-good",
        "name" => "Good",
        "price_rub" => "1",
        "measure_unit" => "g",
        "is_active" => "true",
        "suggested" => "false"
      })

    bad = %{row | "source_key" => "sku-bad", "name" => "Bad", "media_id" => Ecto.UUID.generate()}
    {:ok, book} = ProductWorkbook.encode([row, bad])
    {:ok, preview} = ProductOperations.import_preview(ctx.staff, ctx.target.id, book)
    assert preview.counts == %{new: 1, error: 1}

    assert {:error, {:row, 3, [:invalid_media_reference]}} =
             ProductOperations.apply_changes(ctx.staff, preview)

    assert Relations.list_target_ids("Branch", ctx.target.id, "Product") == []
  end
end
