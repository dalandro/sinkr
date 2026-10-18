defmodule Sinkr.Repo.Migrations.CreateReminders do
  use Ecto.Migration

  def change do
    create table(:reminders) do
      add :title, :string, null: false
      add :cadence, :string, null: false
      # Only for weekly ones: ISO day number, 1 = Monday.
      add :weekday, :integer
      # Local wall-clock time, the way you'd set an alarm.
      add :time, :time, null: false
      add :last_fired_on, :date
      add :acknowledged_on, :date

      timestamps(type: :utc_datetime)
    end
  end
end
