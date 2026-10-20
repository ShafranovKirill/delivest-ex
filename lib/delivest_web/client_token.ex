defmodule DelivestWeb.ClientToken do
  alias DelivestWeb.Endpoint

  @access_salt "client access"
  @refresh_salt "client refresh"
  @access_ttl 15 * 60
  @refresh_ttl 60 * 24 * 60 * 60

  @spec issue(String.t()) :: map()
  def issue(client_id) do
    %{
      access_token: Phoenix.Token.sign(Endpoint, @access_salt, client_id),
      refresh_token: Phoenix.Token.sign(Endpoint, @refresh_salt, client_id),
      expires_in: @access_ttl
    }
  end

  @spec verify_access(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def verify_access(token),
    do: Phoenix.Token.verify(Endpoint, @access_salt, token, max_age: @access_ttl)

  @spec verify_refresh(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def verify_refresh(token),
    do: Phoenix.Token.verify(Endpoint, @refresh_salt, token, max_age: @refresh_ttl)
end
