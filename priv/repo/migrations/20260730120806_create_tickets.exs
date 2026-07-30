defmodule Sinkr.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      add :title, :string, null: false
      add :category, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :priority, :integer, null: false, default: 2
      add :next_step, :text

      timestamps(type: :utc_datetime)
    end
  end
end
