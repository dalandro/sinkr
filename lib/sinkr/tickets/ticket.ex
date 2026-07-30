defmodule Sinkr.Tickets.Ticket do
  @moduledoc """
  A loose end worth coming back to.

  `status` is yours and yours alone — set by hand, and nothing in the app may
  move it on your behalf.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # Ordered the way the list shows them: what you're on, what's stuck, what's
  # waiting, then the two kinds of not-now. Ecto.Enum doesn't care about order,
  # so this one list is both the valid set and the display order.
  @statuses [:active, :blocked, :queued, :parked, :done]
  @categories [:bug, :feature, :review, :experiment, :chore, :idea]

  schema "tickets" do
    field :title, :string
    field :category, Ecto.Enum, values: @categories
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :priority, :integer, default: 2
    field :next_step, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The statuses a ticket can be in, in the order they're listed to you."
  def statuses, do: @statuses

  @doc "The categories a ticket can have."
  def categories, do: @categories

  @doc """
  How a ticket is named in the UI and in URLs — `s-12`.

  Derived from the id rather than stored, so it can never drift out of step
  with the row it names.
  """
  def display_ref(%__MODULE__{id: id}), do: "s-#{id}"

  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:title, :category, :status, :priority, :next_step])
    |> validate_required([:title, :category])
  end
end
