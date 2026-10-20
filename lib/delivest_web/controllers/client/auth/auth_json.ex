defmodule DelivestWeb.Client.Auth.AuthJSON do
  alias DelivestWeb.Client.Profile.ProfileJSON

  def start(%{confirmation: confirmation, call_number: call_number, expires_in: expires_in}) do
    %{
      data: %{
        confirmation_id: confirmation.id,
        call_number: call_number,
        expires_in: expires_in
      }
    }
  end

  def pending(_assigns), do: %{data: %{status: "pending"}}

  def session(%{client: client, tokens: tokens}) do
    %{
      data:
        tokens |> Map.put(:status, "confirmed") |> Map.put(:client, ProfileJSON.client(client))
    }
  end
end
