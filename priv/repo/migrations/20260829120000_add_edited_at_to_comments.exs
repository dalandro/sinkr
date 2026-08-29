defmodule Sinkr.Repo.Migrations.AddEditedAtToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :edited_at, :utc_datetime
    end
  end
end
