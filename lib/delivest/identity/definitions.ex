defmodule Delivest.Identity.Definitions do
  @permissions ~w"""
  staff.create staff.read staff.update staff.delete
  roles.create roles.read roles.update roles.delete
  branches.create branches.read branches.update branches.delete
  categories.create categories.read categories.update categories.delete
  products.create products.read products.update products.delete
  admin
  """

  def permissions, do: @permissions
end
