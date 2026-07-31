defmodule Sinkr.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  def change do
    create table(:snapshots) do
      add :sinker_id, references(:sinkers, on_delete: :delete_all), null: false
      add :sha256, :string, null: false
      add :filename, :string, null: false
      add :mime, :string, null: false
      add :byte_size, :integer, null: false
      add :pinned_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:snapshots, [:sinker_id])
  end
end
