defmodule Sinkr.RemindersTest do
  use Sinkr.DataCase

  alias Sinkr.Reminders
  alias Sinkr.Reminders.Reminder

  describe "create_reminder/1" do
    test "a daily reminder needs a title and a time" do
      assert {:ok, %Reminder{cadence: :daily, weekday: nil}} =
               Reminders.create_reminder(%{
                 title: "Check Linear inbox",
                 cadence: :daily,
                 time: ~T[09:00:00]
               })

      assert {:error, changeset} =
               Reminders.create_reminder(%{cadence: :daily, time: ~T[09:00:00]})

      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "a weekly reminder needs a weekday too" do
      assert {:error, changeset} =
               Reminders.create_reminder(%{
                 title: "Run npx",
                 cadence: :weekly,
                 time: ~T[09:00:00]
               })

      assert %{weekday: ["can't be blank"]} = errors_on(changeset)

      assert {:ok, %Reminder{weekday: 5}} =
               Reminders.create_reminder(%{
                 title: "Run npx",
                 cadence: :weekly,
                 weekday: 5,
                 time: ~T[09:00:00]
               })
    end
  end

  describe "update_reminder/2" do
    test "reschedules a reminder, dropping the weekday when it goes daily" do
      {:ok, reminder} =
        Reminders.create_reminder(%{
          title: "Run npx",
          cadence: :weekly,
          weekday: 5,
          time: ~T[09:00:00]
        })

      assert {:ok,
              %Reminder{title: "Run npx -g", cadence: :daily, weekday: nil, time: ~T[17:30:00]}} =
               Reminders.update_reminder(reminder, %{
                 title: "Run npx -g",
                 cadence: :daily,
                 time: ~T[17:30:00]
               })

      assert {:error, changeset} = Reminders.update_reminder(reminder, %{title: ""})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "due?/2" do
    # A Friday.
    @friday_nine ~N[2026-10-16 09:00:00]

    test "a daily reminder is due from its time on, once a day" do
      reminder = %Reminder{cadence: :daily, time: ~T[09:00:00]}

      refute Reminders.due?(reminder, ~N[2026-10-16 08:59:00])
      assert Reminders.due?(reminder, @friday_nine)
      assert Reminders.due?(reminder, ~N[2026-10-16 17:30:00])
      refute Reminders.due?(%{reminder | last_fired_on: ~D[2026-10-16]}, ~N[2026-10-16 17:30:00])
      assert Reminders.due?(%{reminder | last_fired_on: ~D[2026-10-15]}, @friday_nine)
    end

    test "a weekly reminder is due only on its weekday" do
      reminder = %Reminder{cadence: :weekly, weekday: 5, time: ~T[09:00:00]}

      assert Reminders.due?(reminder, @friday_nine)
      refute Reminders.due?(reminder, ~N[2026-10-17 09:00:00])
      refute Reminders.due?(reminder, ~N[2026-10-16 08:59:00])
    end
  end

  describe "fire_due/1" do
    test "fires what's due, stamps it, and broadcasts it" do
      Reminders.subscribe()

      {:ok, due} =
        Reminders.create_reminder(%{
          title: "Run npx",
          cadence: :weekly,
          weekday: 5,
          time: ~T[09:00:00]
        })

      {:ok, _later} =
        Reminders.create_reminder(%{title: "Lunch", cadence: :daily, time: ~T[12:00:00]})

      assert [%Reminder{id: id, last_fired_on: ~D[2026-10-16]}] =
               Reminders.fire_due(~N[2026-10-16 09:00:30])

      assert id == due.id
      assert_receive {:reminders_fired, [%Reminder{id: ^id}]}

      # Same minute again: already fired today, nothing more to say.
      assert [] = Reminders.fire_due(~N[2026-10-16 09:01:00])
      refute_receive {:reminders_fired, _}
    end
  end

  describe "ringing?/1 and acknowledge/1" do
    test "rings from firing until acknowledged" do
      {:ok, reminder} =
        Reminders.create_reminder(%{title: "Run npx", cadence: :daily, time: ~T[09:00:00]})

      refute Reminders.ringing?(reminder)

      [reminder] = Reminders.fire_due(~N[2026-10-16 09:00:00])
      assert Reminders.ringing?(reminder)

      {:ok, reminder} = Reminders.acknowledge(reminder)
      refute Reminders.ringing?(reminder)

      # Tomorrow's ring is tomorrow's business — yesterday's acknowledgement doesn't cover it.
      [reminder] = Reminders.fire_due(~N[2026-10-17 09:00:00])
      assert Reminders.ringing?(reminder)
    end

    test "a ring nobody saw carries over to the next day" do
      {:ok, reminder} =
        Reminders.create_reminder(%{
          title: "Run npx",
          cadence: :weekly,
          weekday: 5,
          time: ~T[09:00:00]
        })

      [reminder] = Reminders.fire_due(~N[2026-10-16 09:00:00])
      assert Reminders.ringing?(reminder)
      assert [] = Reminders.fire_due(~N[2026-10-19 09:00:00])
      assert Reminders.ringing?(Reminders.get_reminder!(reminder.id))
    end
  end

  describe "schedule_label/1" do
    test "reads the way you'd say it" do
      assert Reminders.schedule_label(%Reminder{cadence: :daily, time: ~T[09:00:00]}) ==
               "daily 09:00"

      assert Reminders.schedule_label(%Reminder{cadence: :weekly, weekday: 5, time: ~T[09:00:00]}) ==
               "Fri 09:00"
    end
  end
end
