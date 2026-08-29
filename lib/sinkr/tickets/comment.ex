defmodule Sinkr.Tickets.Comment do
  @moduledoc """
  A note left on a ticket — what you found, what you'd do next.

  Comments are the ticket's running log. The newest one is, in practice, the
  current "next step"; older ones are how you got there. A comment can be
  edited — for the typo, the wrong ticket number — but it says so afterwards,
  so the trail stays honest.

  `edited_at` is its own column rather than "updated_at differs from
  inserted_at": the timestamps are whole seconds, so an edit made right after
  posting would otherwise vanish without trace.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :body, :string
    field :edited_at, :utc_datetime

    belongs_to :ticket, Sinkr.Tickets.Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
  end

  @doc "Marks the comment as edited, right now."
  def edit_changeset(comment, attrs) do
    comment
    |> changeset(attrs)
    |> put_change(:edited_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc "Whether the comment has been changed since it was left."
  def edited?(%__MODULE__{edited_at: edited_at}), do: not is_nil(edited_at)

  @doc """
  When the comment was left, to the minute — the same string in the pane and
  in `sinkr show`, so what you read in one you'll recognise in the other.
  """
  def stamp(%__MODULE__{inserted_at: at}), do: format(at)

  @doc "When the comment was last edited, in the same shape as `stamp/1`."
  def edited_stamp(%__MODULE__{edited_at: at}), do: format(at)

  defp format(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
end
