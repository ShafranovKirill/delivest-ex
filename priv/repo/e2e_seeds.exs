alias Delivest.{Relations, Repo}
alias Delivest.Identity.{Branch, RolePresets, Role, Staff, Staffs}
alias Delivest.Identity.Branch.BranchInfo
alias Delivest.Net.{Category, Product}

import Ecto.Query

password = "E2ePassword123!"

hours =
  Map.new(
    ~w(monday tuesday wednesday thursday friday saturday sunday),
    &{&1, %{"open" => "00:00", "close" => "23:59", "enabled" => true}}
  )

RolePresets.seed()

branch =
  Repo.get_by(Branch, slug: "e2e") ||
    %Branch{}
    |> Branch.changeset(%{name: "E2E", slug: "e2e", code: "E2E", is_active: true})
    |> Repo.insert!()

Repo.get_by(BranchInfo, branch_id: branch.id) ||
  %BranchInfo{board_token: "e2e-board"}
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
      {"e2e_courier", "Курьер", "Курьер"}
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

    for {name, price, order} <- [{"Маргарита", 590, 1.0}, {"Пепперони", 690, 2.0}] do
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

IO.puts("E2E data is ready")
