defmodule Sinkr.Reminders.Scheduler do
  @moduledoc """
  The clock behind reminders: checks what's due on an interval and, for each
  ring, hands the title to the desktop notifier. The context decides what's
  due and broadcasts it; this process only owns the tick and the notifying.

  Always running outside test; tests start their own with a clock and a
  notifier they control.
  """

  use GenServer

  alias Sinkr.Reminders
  alias Sinkr.Reminders.DesktopNotifier

  @default_interval_ms 30_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    state = %{
      clock: Keyword.get(opts, :clock, &Reminders.local_now/0),
      notifier: Keyword.get(opts, :notifier, &DesktopNotifier.notify/1),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms)
    }

    send(self(), :tick)

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state.clock.()
    |> Reminders.fire_due()
    |> Enum.each(&state.notifier.(&1.title))

    Process.send_after(self(), :tick, state.interval_ms)

    {:noreply, state}
  end
end
