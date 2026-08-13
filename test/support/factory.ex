defmodule Delivest.Factory do
  use ExMachina.Ecto, repo: Delivest.Repo

  alias Delivest.Identity.{Staff, Role}

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
end
