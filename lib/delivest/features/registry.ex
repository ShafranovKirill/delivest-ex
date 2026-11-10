defmodule Delivest.Features.Registry do
  @moduledoc "Allowlisted host-managed feature keys, independent of background jobs."
  @features ["segments"]

  def known?(feature), do: feature in @features
end
