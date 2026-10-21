defmodule DelivestWeb.ClientToken do
  alias DelivestWeb.Endpoint

  @access_salt "client access"
  @refresh_salt "client refresh"
  @socket_salt "client socket"
  @socket_ttl 24 * 60 * 60
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

  @spec issue_socket(String.t() | nil, String.t() | nil) :: String.t()
  def issue_socket(session_id, client_id),
    do:
      Phoenix.Token.sign(Endpoint, @socket_salt, %{session_id: session_id, client_id: client_id})

  @spec verify_socket(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify_socket(token),
    do: Phoenix.Token.verify(Endpoint, @socket_salt, token, max_age: @socket_ttl)

  @spec verify_refresh(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def verify_refresh(token),
    do: Phoenix.Token.verify(Endpoint, @refresh_salt, token, max_age: @refresh_ttl)
end
