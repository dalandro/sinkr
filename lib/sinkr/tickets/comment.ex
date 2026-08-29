defmodule Sinkr.Tickets.Comment do
  @moduledoc """
  A note left on a ticket — what you found, what you'd do next.

  Comments are the ticket's running log. The newest one is, in practice, the
  current "next step"; older ones are how you got there. Nothing is ever
  edited in place: a change of mind is a new comment, so the trail stays
  honest.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :body, :string

    belongs_to :ticket, Sinkr.Tickets.Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
  end

  @doc """
  When the comment was left, to the minute — the same string in the pane and
  in `sinkr show`, so what you read in one you'll recognise in the other.
  """
  def stamp(%__MODULE__{inserted_at: at}), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
end
