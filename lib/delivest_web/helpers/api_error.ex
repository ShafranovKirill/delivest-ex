defmodule DelivestWeb.Helpers.ApiError do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @spec send_error(
          Plug.Conn.t(),
          atom() | integer(),
          atom() | String.t(),
          String.t(),
          map() | nil
        ) ::
          Plug.Conn.t()
  def send_error(conn, status, code, message, details \\ nil) do
    body = %{error: to_string(code), message: message}
    body = if details, do: Map.put(body, :details, details), else: body

    conn
    |> put_status(status)
    |> json(body)
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  def changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
