defmodule Delivest.Identity.Definitions do
  @permissions ~w"""
  staff.create staff.read staff.update staff.delete
  roles.create roles.read roles.update roles.delete
  branches.create branch.read branch.update branch.delete
  admin
  """

  def permissions, do: @permissions
end
