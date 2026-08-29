defmodule Sinkr.Repo.Migrations.MoveNextStepIntoComments do
  use Ecto.Migration

  @moduledoc """
  The single "next step" field becomes the first comment on its ticket.

  Stamped with the ticket's `updated_at`: the closest thing on record to when
  that next step was last written. Blank next steps carry no information and
  aren't copied.
  """

  def up do
    execute """
    INSERT INTO comments (ticket_id, body, inserted_at, updated_at)
    SELECT id, next_step, updated_at, updated_at
    FROM tickets
    WHERE next_step IS NOT NULL AND trim(next_step) <> ''
    """

    alter table(:tickets) do
      remove :next_step
    end
  end

  # Puts the newest comment back as the next step. The comments themselves
  # stay; the migration before this one owns that table.
  def down do
    alter table(:tickets) do
      add :next_step, :text
    end

    execute """
    UPDATE tickets
    SET next_step = (
      SELECT body FROM comments
      WHERE comments.ticket_id = tickets.id
      ORDER BY inserted_at DESC, id DESC
      LIMIT 1
    )
    """
  end
end
