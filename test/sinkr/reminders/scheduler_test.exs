defmodule Sinkr.Reminders.SchedulerTest do
  @moduledoc """
  The scheduler is the clock: it asks the context what's due on an interval,
  and for each ring hands the title to the desktop notifier. Everything it
  reads comes from the context; the only thing it owns is the tick.
  """

  # async: false so the scheduler process shares this test's DB sandbox.
  use Sinkr.DataCase, async: false

  alias Sinkr.Reminders
  alias Sinkr.Reminders.Scheduler

  setup do
    {:ok, reminder} =
      Reminders.create_reminder(%{title: "Run npx", cadence: :daily, time: ~T[09:00:00]})

    %{reminder: reminder}
  end

  test "fires what's due on start and tells the notifier", %{reminder: reminder} do
    Reminders.subscribe()
    test_pid = self()

    start_supervised!(
      {Scheduler,
       clock: fn -> ~N[2026-10-16 09:00:00] end,
       notifier: fn title -> send(test_pid, {:notified, title}) end}
    )

    id = reminder.id
    assert_receive {:reminders_fired, [%{id: ^id}]}
    assert_receive {:notified, "Run npx"}
  end

  test "keeps checking on the interval, firing once per day" do
    Reminders.subscribe()
    test_pid = self()
    # Each tick reads one day later than the last, so a second ring proves
    # the timer re-armed rather than the first tick firing twice.
    {:ok, days} = Agent.start_link(fn -> 0 end)

    start_supervised!(
      {Scheduler,
       clock: fn ->
         day = Agent.get_and_update(days, &{&1, &1 + 1})
         NaiveDateTime.add(~N[2026-10-16 09:00:00], day, :day)
       end,
       notifier: fn title -> send(test_pid, {:notified, title}) end,
       interval_ms: 10}
    )

    assert_receive {:notified, "Run npx"}
    assert_receive {:notified, "Run npx"}
  end

  test "nothing due, nothing said" do
    Reminders.subscribe()
    test_pid = self()

    start_supervised!(
      {Scheduler,
       clock: fn -> ~N[2026-10-16 08:00:00] end,
       notifier: fn title -> send(test_pid, {:notified, title}) end}
    )

    refute_receive {:notified, _}, 50
    refute_receive {:reminders_fired, _}
  end
end
