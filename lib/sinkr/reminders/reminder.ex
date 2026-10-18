defmodule Sinkr.Reminders.Reminder do
  @moduledoc """
  A nudge on a schedule — "Friday morning, run npx", "9am, check Linear".

  Two cadences only, daily and weekly, because that's what a standing nudge
  looks like; a cron string would let you say more than you'd ever want to.
  `time` is local wall-clock, the way an alarm is set, so it's never shifted
  through a zone. The two dates are how a ring is remembered: `last_fired_on`
  stops the same day firing twice, `acknowledged_on` turns the ring off.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @cadences [:daily, :weekly]

  # ISO day numbers, so `Date.day_of_week/1` is the whole comparison.
  @weekdays [
    {1, "Mon"},
    {2, "Tue"},
    {3, "Wed"},
    {4, "Thu"},
    {5, "Fri"},
    {6, "Sat"},
    {7, "Sun"}
  ]

  schema "reminders" do
    field :title, :string
    field :cadence, Ecto.Enum, values: @cadences, default: :daily
    field :weekday, :integer
    field :time, :time
    field :last_fired_on, :date
    field :acknowledged_on, :date

    timestamps(type: :utc_datetime)
  end

  @doc "The cadences a reminder can have."
  def cadences, do: @cadences

  @doc "The weekdays a weekly reminder can fall on, Monday first, with their short names."
  def weekdays, do: @weekdays

  @doc "The short name of an ISO weekday number, e.g. `5` is `\"Fri\"`."
  def weekday_label(weekday) do
    {^weekday, label} = Enum.find(@weekdays, &(elem(&1, 0) == weekday))
    label
  end

  @doc false
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:title, :cadence, :weekday, :time])
    |> validate_required([:title, :cadence, :time])
    |> validate_weekday()
  end

  # A weekly reminder without a weekday would never fire; a daily one with a
  # weekday would carry a lie, so it's dropped rather than kept.
  defp validate_weekday(changeset) do
    case get_field(changeset, :cadence) do
      :weekly ->
        changeset
        |> validate_required([:weekday])
        |> validate_inclusion(:weekday, Enum.map(@weekdays, &elem(&1, 0)))

      :daily ->
        put_change(changeset, :weekday, nil)

      nil ->
        changeset
    end
  end
end
