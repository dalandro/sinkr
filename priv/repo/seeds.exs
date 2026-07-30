# Script for populating the database. Run it with:
#
#     mix run priv/repo/seeds.exs
#
# Real seed data is personal — actual tickets name actual clients and actual
# work — so it doesn't belong in a public repo. It lives in `seeds.local.exs`
# instead, which is gitignored. This file just runs that one if you have it,
# which keeps `mix ecto.setup` working on a fresh clone without shipping
# anybody's loose ends.

local_seeds = Path.join(__DIR__, "seeds.local.exs")

if File.exists?(local_seeds) do
  Code.eval_file(local_seeds)
else
  IO.puts("No priv/repo/seeds.local.exs, so nothing to seed.")
end
