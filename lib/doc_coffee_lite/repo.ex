defmodule DocCoffeeLite.Repo do
  use Ecto.Repo,
    otp_app: :doc_coffee_lite,
    adapter: Ecto.Adapters.Postgres
end
