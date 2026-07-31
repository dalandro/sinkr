defmodule Sinkr.Repo.Migrations.CreateSinkers do
  use Ecto.Migration

  def change do
    create table(:sinkers) do
      add :ticket_id, references(:tickets, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :value, :string, null: false
      add :origin, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sinkers, [:ticket_id])
  end
end
