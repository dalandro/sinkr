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

  # Priority answers "when", not "does this matter". Bounded, so every level a
  # ticket can be at has a meaning attached to it.
  @priorities [
    {0, "Drop everything"},
    {1, "This week"},
    {2, "Soon"},
    {3, "Someday"}
  ]

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
  The priority levels, most pressing first, each with what it actually means.

  Priority is about *when*, not importance — everything here is worth doing or
  it wouldn't be a ticket. Change the wording in `@priorities` and it changes
  everywhere at once.
  """
  def priorities, do: @priorities

  @doc "What a priority level means, e.g. `0` is #{inspect(elem(hd(@priorities), 1))}."
  def priority_label(priority) do
    {^priority, label} = Enum.find(@priorities, &(elem(&1, 0) == priority))
    label
  end

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
    |> validate_inclusion(:priority, Enum.map(@priorities, &elem(&1, 0)))
  end
end
