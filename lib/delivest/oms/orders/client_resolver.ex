defmodule Delivest.Oms.Orders.ClientResolver do
  alias Delivest.Identity

  def resolve(attrs, opts \\ []) do
    if valid_phone?(attrs["customer_phone"]) do
      attrs |> Identity.resolve_client(opts) |> ensure_not_blocked()
    else
      {:ok, nil}
    end
  end

  defp ensure_not_blocked({:ok, client_id} = result) do
    if Identity.client_blocked?(client_id), do: {:error, :client_blocked}, else: result
  end

  defp ensure_not_blocked(error), do: error

  defp valid_phone?(phone) when is_binary(phone), do: Regex.match?(Identity.phone_regex(), phone)
  defp valid_phone?(_phone), do: false
end
