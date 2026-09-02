defmodule Sinkr.Repo.Migrations.AddAgentSessionIdsToEpisodes do
  use Ecto.Migration

  def change do
    alter table(:episodes) do
      add :agent_session_ids, :text, null: false, default: "[]"
    end
  end
end
