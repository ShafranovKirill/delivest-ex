alias Delivest.{Relations, Repo}
alias Delivest.Identity.{Branch, RolePresets, Role, Staff, Staffs}
alias Delivest.Identity.Branch.BranchInfo
alias Delivest.Net.{Category, Product}
alias Delivest.Oms.{Carts, Order, Orders}
alias Delivest.Integrations.Zvonok

import Ecto.Query

password = "E2ePassword123!"

hours =
  Map.new(
    ~w(monday tuesday wednesday thursday friday saturday sunday),
    &{&1, %{"open" => "00:00", "close" => "23:59", "enabled" => true}}
  )

RolePresets.seed()

# The dev-only phone confirmation shortcut lets browser tests sign in as distinct
# clients without contacting an external calling provider.
unless Repo.one(Zvonok.Settings) do
  %Zvonok.Settings{}
  |> Zvonok.Settings.changeset(%{
    public_key: "e2e-public-key",
    campaign_id: "e2e-campaign",
    webhook_token: "e2e-webhook-token",
    enabled: true,
    dev_skip_calls: true
  })
  |> Repo.insert!()
end

branch =
  Repo.get_by(Branch, slug: "e2e") ||
    %Branch{}
    |> Branch.changeset(%{name: "E2E", slug: "e2e", code: "E2E", is_active: true})
    |> Repo.insert!()

Repo.get_by(BranchInfo, branch_id: branch.id) ||
  %BranchInfo{
    board_token: "e2e-board",
    fiscal: %Delivest.Fiscal.BranchSettings{
      mode: :own,
      inn: "5544332219",
      payment_address: "https://v5.online.atol.ru",
      email: "e2e@example.com",
      atol: %Delivest.Integrations.AtolOnline.Settings{
        login: "e2e",
        password: "e2e",
        group_code: "e2e-group",
        callback_token: "e2e"
      }
    }
  }
  |> BranchInfo.changeset(%{
    branch_id: branch.id,
    address: "Москва, Тверская улица, 7",
    city: "Москва",
    latitude: 55.757718,
    longitude: 37.611347,
    phone_number: "+74951234567",
    delivery_time: 45,
    working_hours: hours,
    kitchen: %{enabled: true, lead_minutes: 90},
    couriers: %{source: :staff, search: :preparing}
  })
  |> Repo.insert!()

role = fn name -> Repo.one!(from r in Role, where: r.name == ^name) end

for {login, name, role_name} <- [
      {"e2e_admin", "Админ", "Администратор"},
      {"e2e_operator", "Оператор", "Оператор"},
      {"e2e_kitchen", "Кухня", "Кухня"},
      {"e2e_courier", "Курьер", "Курьер"},
      {"e2e_cashier", "Кассир", "Кассир"}
    ],
    is_nil(Repo.get_by(Staff, login: login)) do
  {:ok, _staff} =
    Staffs.system_create_staff(%{
      login: login,
      name: name,
      password: password,
      password_confirmation: password,
      role_id: role.(role_name).id,
      branch_ids: [branch.id]
    })
end

category_ids = Relations.list_target_ids("Branch", branch.id, "Category")

unless Repo.exists?(from c in Category, where: c.id in ^category_ids) do
  Repo.transaction(fn ->
    category =
      %Category{}
      |> Category.changeset(%{name: "Пицца", order: 1.0, is_active: true})
      |> Repo.insert!()

    {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id, %{})

    for {name, price, order} <- [{"Маргарита", 59_000, 1.0}, {"Пепперони", 69_000, 2.0}] do
      product =
        %Product{order: order}
        |> Product.changeset(%{
          name: name,
          price: price,
          weight: 450,
          category_id: category.id,
          slug: "e2e-#{order |> trunc()}",
          is_active: true
        })
        |> Repo.insert!()

      {:ok, _} = Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id, %{})
    end
  end)
end

# A separate, inactive branch with enough orders to exercise the pickup board paging.
# It stays inactive so it does not appear in the customer branch picker.
board_branch =
  Repo.get_by(Branch, slug: "e2e-board") ||
    %Branch{}
    |> Branch.changeset(%{name: "E2E Board", slug: "e2e-board", code: "E2EB", is_active: false})
    |> Repo.insert!()

if board_branch.is_active do
  board_branch |> Ecto.Changeset.change(is_active: false) |> Repo.update!()
end

unless Repo.get_by(BranchInfo, branch_id: board_branch.id) do
  Repo.insert!(%BranchInfo{branch_id: board_branch.id, board_token: "e2e-board-many"})
end

category = Repo.get_by!(Category, name: "Пицца")
product = Repo.get_by!(Product, slug: "e2e-1")

unless Relations.related?("Branch", board_branch.id, "Product", product.id) do
  {:ok, _} =
    Relations.create_relation(Repo, "Branch", board_branch.id, "Product", product.id, %{})
end

order_count = 40

existing_orders =
  Repo.aggregate(from(o in Order, where: o.branch_id == ^board_branch.id), :count)

if existing_orders < order_count do
  for index <- (existing_orders + 1)..order_count//1 do
    {:ok, cart} =
      Carts.create_cart(%{session_id: "e2e-board-#{index}", branch_id: board_branch.id})

    {:ok, _, _} = Carts.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Orders.create_order(%{
        "cart_id" => cart.id,
        "branch_id" => board_branch.id,
        "fulfillment_type" => "pickup",
        "payment_method" => "cash"
      })

    status = if rem(index, 2) == 0, do: :preparing, else: :ready

    order
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end
end

IO.puts("E2E data is ready")
