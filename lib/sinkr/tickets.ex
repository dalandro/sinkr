defmodule Sinkr.Tickets do
  @moduledoc """
  Your loose ends.
  """

  import Ecto.Query, only: [from: 2]

  alias Sinkr.Repo
  alias Sinkr.Tickets.Ticket

  @doc "Every ticket, newest first."
  def list_tickets do
    Repo.all(from t in Ticket, order_by: [desc: t.inserted_at, desc: t.id])
  end

  @doc """
  Finds the ticket a `s-12` style ref names.

  Anything that isn't a ref for a real ticket — a typo, a stale bookmark —
  raises `Ecto.NoResultsError`, the same as an id that doesn't exist, so
  callers have one failure to handle rather than two.
  """
  def get_ticket_by_ref!(ref) do
    case Integer.parse(String.trim_leading(ref, "s-")) do
      {id, ""} -> Repo.get!(Ticket, id)
      _ -> raise Ecto.NoResultsError, queryable: Ticket
    end
  end

  @doc "Opens a new ticket. It starts queued; you move it from there yourself."
  def create_ticket(attrs) do
    %Ticket{}
    |> Ticket.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Edits a ticket. Status moves only ever come through here, from you."
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.changeset(attrs)
    |> Repo.update()
  end

  @doc "Throws a ticket away for good."
  def delete_ticket(%Ticket{} = ticket), do: Repo.delete(ticket)

  @doc "A blank changeset for the ticket form to render from."
  def change_ticket(%Ticket{} = ticket, attrs \\ %{}), do: Ticket.changeset(ticket, attrs)

  @doc """
  Buckets tickets by status, in the order statuses are listed to you.

  Within a bucket the most pressing ticket comes first — priority 0 is the
  drop-everything end of the scale. Statuses nothing is sitting in are left out
  entirely, so the list never shows an empty heading.
  """
  def group_by_status(tickets) do
    by_status = Enum.group_by(tickets, & &1.status)

    Ticket.statuses()
    |> Enum.map(&{&1, by_status |> Map.get(&1, []) |> Enum.sort_by(fn t -> t.priority end)})
    |> Enum.reject(fn {_status, tickets} -> tickets == [] end)
  end
end
