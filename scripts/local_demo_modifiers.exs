import Ecto.Query
alias Delivest.Repo
alias Delivest.Net.{Modifier, ModifierGroup, Product, ProductModifierGroup}

repo = Application.fetch_env!(:delivest, Repo)

if Mix.env() != :dev or repo[:database] != "delivest_f01_demo_local" or
     repo[:hostname] not in ["localhost", "127.0.0.1"] do
  raise "Modifier demo requires the dedicated loopback demo database"
end

fixtures = [
  {"Sizes", "Размер", 1, 1, true, [{"Стандарт", 0, true}, {"Большой", 12_000, false}]},
  {"Extras", "Добавки", 0, 3, false,
   [{"Сыр", 6_000, false}, {"Бекон", 9_000, false}, {"Соус", 3_000, false}]},
  {"Drinks", "Сироп", 0, 2, false,
   [{"Ваниль", 3_000, false}, {"Карамель", 3_000, false}, {"Кокос", 4_000, false}]}
]

fixture_id = fn name ->
  <<a::32, b::16, c::16, d::16, e::48, _::binary>> =
    :crypto.hash(:sha256, "delivest-local-demo:#{name}")

  Ecto.UUID.load!(<<a::32, b::16, c::16, d::16, e::48>>)
end

{:ok, _} =
  Repo.transaction(fn ->
    groups =
      for {key, name, min, max, is_size, options} <- fixtures, into: %{} do
        id = fixture_id.("group:#{key}")
        group = Repo.get(ModifierGroup, id) || %ModifierGroup{id: id}
        attrs = %{name: name, min: min, max: max, is_size: is_size, position: 10}
        group = Repo.insert_or_update!(ModifierGroup.changeset(group, attrs))

        for {{label, price, default}, index} <- Enum.with_index(options) do
          modifier_id = fixture_id.("modifier:#{key}:#{label}")
          modifier = Repo.get(Modifier, modifier_id) || %Modifier{id: modifier_id}
          attrs = %{group_id: id, name: label, price: price, is_default: default, position: index}
          Repo.insert_or_update!(Modifier.changeset(modifier, attrs))
        end

        {key, group.id}
      end

    fixture_path = Path.expand("../../examples/demo-menu/catalog.json", __DIR__)

    product_ids =
      fixture_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("products")
      |> Enum.map(& &1["product_id"])

    products = Repo.all(from p in Product, where: p.id in ^product_ids, select: {p.id, p.name})
    if products == [], do: raise("Apply photo menu before modifiers")

    for {id, name} <- products do
      keys =
        if String.contains?(name, ["Пицца", "Бургер", "Маргарита", "Пепперони"]),
          do: ["Sizes", "Extras"],
          else: ["Extras"]

      keys = if String.contains?(name, ["Кофе", "Капучино", "Латте"]), do: ["Drinks"], else: keys

      for {key, index} <- Enum.with_index(keys) do
        group_id = Map.fetch!(groups, key)

        exists? =
          Repo.exists?(
            from l in ProductModifierGroup, where: l.product_id == ^id and l.group_id == ^group_id
          )

        unless exists?,
          do:
            Repo.insert!(%ProductModifierGroup{
              product_id: id,
              group_id: group_id,
              position: index
            })
      end
    end
  end)

IO.puts("Demo modifiers ready")
