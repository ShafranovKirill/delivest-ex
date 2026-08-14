defmodule Delivest.Net do
  alias Delivest.Net.{Branches}

  defdelegate get_branch(id), to: Branches
end
