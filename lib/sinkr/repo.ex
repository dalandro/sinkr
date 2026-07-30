defmodule Sinkr.Repo do
  use Ecto.Repo,
    otp_app: :sinkr,
    adapter: Ecto.Adapters.SQLite3
end
