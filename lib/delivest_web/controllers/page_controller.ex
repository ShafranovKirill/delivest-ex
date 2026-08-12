defmodule DelivestWeb.PageController do
  use DelivestWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
