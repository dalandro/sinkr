defmodule Sinkr.Reminders do
  @moduledoc """
  Standing nudges on a schedule.

  The clock here is local wall-clock time (`local_now/0`), never UTC: a 9am
  reminder means 9am where the machine is. A reminder fires at most once a
  day, from its time on — so a server that was down at 9 still rings when
  it comes up at 10, but a Friday reminder missed entirely waits for next
  Friday. Firing is a date stamp, acknowledging is another; a reminder
  rings from the moment the two differ until you say Done, so a ring you
  didn't see on Friday is still there on Monday.
  """

  import Ecto.Query, only: [from: 2]

  alias Sinkr.Reminders.Reminder
  alias Sinkr.Repo

  @doc "Every reminder, earliest in the day first."
  def list_reminders do
    Repo.all(from r in Reminder, order_by: [asc: r.time, asc: r.id])
  end

  @doc "Sets a new reminder."
  def create_reminder(attrs) do
    %Reminder{}
    |> Reminder.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Reschedules or renames a reminder."
  def update_reminder(%Reminder{} = reminder, attrs) do
    reminder
    |> Reminder.changeset(attrs)
    |> Repo.update()
  end

  @doc "Drops a reminder for good."
  def delete_reminder(%Reminder{} = reminder), do: Repo.delete(reminder)

  @doc "Finds a reminder by id."
  def get_reminder!(id), do: Repo.get!(Reminder, id)

  @doc "A blank changeset for the reminder form to render from."
  def change_reminder(%Reminder{} = reminder, attrs \\ %{}),
    do: Reminder.changeset(reminder, attrs)

  @doc "The machine's wall-clock now — the one clock every schedule is read against."
  def local_now, do: NaiveDateTime.local_now()

  @doc """
  Whether the reminder should ring at `now`: not yet fired today, today is
  one of its days, and its time has come.
  """
  def due?(%Reminder{} = reminder, %NaiveDateTime{} = now) do
    today = NaiveDateTime.to_date(now)

    reminder.last_fired_on != today and
      day_matches?(reminder, today) and
      Time.compare(NaiveDateTime.to_time(now), reminder.time) != :lt
  end

  defp day_matches?(%Reminder{cadence: :daily}, _today), do: true

  defp day_matches?(%Reminder{cadence: :weekly, weekday: weekday}, today),
    do: Date.day_of_week(today) == weekday

  @doc """
  Rings everything due at `now`: stamps each with today, broadcasts the lot
  as `{:reminders_fired, reminders}`, and returns them. Nothing due, nothing
  broadcast. Read and stamps share one transaction, so a Remove landing
  mid-batch can't leave an earlier reminder stamped but never rung.
  """
  def fire_due(%NaiveDateTime{} = now) do
    today = NaiveDateTime.to_date(now)

    {:ok, fired} =
      Repo.transaction(fn ->
        list_reminders()
        |> Enum.filter(&due?(&1, now))
        |> Enum.map(fn reminder ->
          reminder
          |> Ecto.Changeset.change(last_fired_on: today)
          |> Repo.update!()
        end)
      end)

    if fired != [], do: broadcast_fired(fired)

    fired
  end

  @doc "Fired, and that ring not yet acknowledged."
  def ringing?(%Reminder{last_fired_on: nil}), do: false
  def ringing?(%Reminder{} = reminder), do: reminder.last_fired_on != reminder.acknowledged_on

  @doc "Turns the current ring off — and only that one, so tomorrow's still rings."
  def acknowledge(%Reminder{} = reminder) do
    reminder
    |> Ecto.Changeset.change(acknowledged_on: reminder.last_fired_on)
    |> Repo.update()
  end

  @doc "The schedule the way you'd say it: `daily 09:00`, `Fri 09:00`."
  def schedule_label(%Reminder{cadence: :daily, time: time}), do: "daily #{format_time(time)}"

  def schedule_label(%Reminder{cadence: :weekly, weekday: weekday, time: time}) do
    "#{Reminder.weekday_label(weekday)} #{format_time(time)}"
  end

  defp format_time(time), do: Calendar.strftime(time, "%H:%M")

  @reminders_topic "reminders"

  @doc "Hears every ring as `{:reminders_fired, reminders}`."
  def subscribe, do: Phoenix.PubSub.subscribe(Sinkr.PubSub, @reminders_topic)

  defp broadcast_fired(reminders) do
    Phoenix.PubSub.broadcast(Sinkr.PubSub, @reminders_topic, {:reminders_fired, reminders})
  end
end
