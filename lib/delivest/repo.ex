defmodule Delivest.Repo do
  use Ecto.Repo,
    otp_app: :delivest,
    adapter: Ecto.Adapters.Postgres
end
