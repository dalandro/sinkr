defmodule Sinkr.Repo.Migrations.CreateComments do
  use Ecto.Migration

  def change do
    create table(:comments) do
      add :ticket_id, references(:tickets, on_delete: :delete_all), null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:ticket_id])
  end
end
