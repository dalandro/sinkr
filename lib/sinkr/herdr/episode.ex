defmodule Sinkr.Herdr.Episode do
  @moduledoc """
  One workspace the poller has ever seen — tethered or not.

  Kept because `herdr workspace list` only shows what's open right now:
  close a workspace and its history is gone unless it was written down as it
  happened. The row carries the label (updated on rename) and when the
  workspace was first and last sighted; which ticket it belonged to is
  derived from the label at read time, same as the live link. `ticket_id`
  is only ever a manual pin — the fallback for a rename that was refused —
  never written by the poller.
  """

  use Ecto.Schema

  schema "episodes" do
    field :workspace_id, :string
    field :label, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :ticket, Sinkr.Tickets.Ticket

    timestamps(type: :utc_datetime)
  end
end
