defmodule Sinkr.Repo.Migrations.CreateEpisodes do
  use Ecto.Migration

  def change do
    create table(:episodes) do
      add :workspace_id, :string, null: false
      add :label, :string, null: false
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
      # Only ever set by hand, as the fallback when a workspace rename is
      # refused; the live link is the label. Outlives its ticket as plain
      # history, so the ref goes rather than the row.
      add :ticket_id, references(:tickets, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:episodes, [:workspace_id])
  end
end
