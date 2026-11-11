defmodule DelivestWeb.AnalyticsIdentity do
  @moduledoc "Signed browser identity shared by funnel and trusted advertising clicks."

  alias DelivestWeb.{Endpoint, Helpers.CookieHelper}

  @cookie "analytics_owner"
  @salt "funnel_guest_owner_v1"

  def cookie_name, do: @cookie

  def put_guest_cookie(conn, id),
    do: CookieHelper.put_cookie(conn, @cookie, Phoenix.Token.sign(Endpoint, @salt, id))

  def guest_or_new(conn) do
    case guest_id(conn) do
      {:ok, id} -> id
      :error -> Ecto.UUID.generate()
    end
  end

  def guest_id(conn) do
    with token when is_binary(token) <- CookieHelper.get_cookie(conn, @cookie),
         {:ok, id} <- Phoenix.Token.verify(Endpoint, @salt, token, max_age: 30 * 86_400),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  def owner(%{assigns: %{current_client: %{id: id}}}), do: {"client:" <> id, nil}

  def owner(conn) do
    case guest_id(conn) do
      {:ok, id} -> {"guest:" <> id, nil}
      :error -> new_guest()
    end
  end

  defp new_guest do
    id = Ecto.UUID.generate()
    {"guest:" <> id, id}
  end
end
