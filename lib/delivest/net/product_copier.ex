defmodule Delivest.Net.ProductCopier do
  @moduledoc "Compatibility wrapper for branch product copies."
  defdelegate copy(staff, selection, from_branch_id, to_branch_id),
    to: Delivest.Net.ProductOperations
end
