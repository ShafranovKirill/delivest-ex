defmodule Delivest.Factory do
  use ExMachina.Ecto, repo: Delivest.Repo

  alias Delivest.Identity.{Staff, Role, StaffBranch, Branch, Client}
  alias Delivest.Net.{Category, Product}

  def role_factory do
    %Role{
      name: sequence(:role_name, &"Role_#{&1}"),
      permissions: ["staff.read", "staff.update"]
    }
  end

  def staff_factory do
    %Staff{
      login: sequence(:login, &"staff_user_#{&1}"),
      password_hash: Argon2.hash_pwd_salt("Q1w2e3r4t5!"),
      role: build(:role)
    }
  end

  def branch_factory do
    %Branch{
      name: sequence(:branch_name, &"Branch_#{&1}"),
      slug: sequence(:branch_slug, &"branch-#{&1}")
    }
  end

  def category_factory do
    %Category{
      name: sequence(:name, &"Category #{&1}"),
      order: 1.0,
      is_active: true
    }
  end

  def product_factory do
    %Product{
      name: sequence(:product_name, &"Product #{&1}"),
      price: 100,
      is_active: true
    }
  end

  def client_factory do
    %Client{
      phone:
        sequence(
          :client_phone,
          &"+7999000#{&1}#{String.pad_leading(Integer.to_string(rem(&1, 10)), 1, "0")}"
        ),
      name: sequence(:client_name, &"Client #{&1}"),
      status: :active
    }
  end

  def promotion_factory do
    %Delivest.Promo.Promotion{
      name: sequence(:promotion_name, &"Promotion #{&1}"),
      kind: :automatic,
      rules: "then discount 10%",
      enabled: true
    }
  end

  def promo_code_factory do
    %Delivest.Promo.PromoCode{code: sequence(:promo_code, &"CODE#{&1}")}
  end

  def insert_promotion(branch_id, attrs) do
    promotion = insert(:promotion, Keyword.put(attrs, :branch_id, branch_id))
    Delivest.Promo.Catalog.invalidate(branch_id)
    promotion
  end

  def insert_code(promotion, attrs \\ []) do
    insert(
      :promo_code,
      Keyword.merge([promotion_id: promotion.id, branch_id: promotion.branch_id], attrs)
    )
  end

  def staff_branch_factory do
    %StaffBranch{
      staff: build(:staff),
      branch: build(:branch)
    }
  end

  def zvonok_settings_factory do
    %Delivest.Integrations.Zvonok.Settings{
      public_key: "zvonok-public-key",
      campaign_id: "123",
      webhook_token: "zvonok-token"
    }
  end

  def insert_branch_product(branch_id, attrs \\ []) do
    product = insert(:product, attrs)

    {:ok, _relation} =
      Delivest.Relations.create_relation(
        Delivest.Repo,
        "Branch",
        branch_id,
        "Product",
        product.id
      )

    product
  end
end
