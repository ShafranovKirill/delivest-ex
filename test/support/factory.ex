defmodule Delivest.Factory do
  use ExMachina.Ecto, repo: Delivest.Repo

  alias Delivest.Identity.{Staff, Role, StaffBranch}
  alias Delivest.Net.{Branch, Category}

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
    %Category{name: sequence(:category_name, &"Category #{&1}")}
  end

  def staff_branch_factory do
    %StaffBranch{
      staff: build(:staff),
      branch: build(:branch)
    }
  end
end
