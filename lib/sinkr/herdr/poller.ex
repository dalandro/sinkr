defmodule Sinkr.Herdr.Poller do
  @moduledoc """
  Asks herdr what's open, on an interval, because herdr has no event stream
  to subscribe to.

  Each tick does three things with one CLI call: broadcasts the workspaces
  over `Sinkr.Herdr.subscribe/0` for whatever's rendering, answers
  `current/1` for a LiveView that mounts between ticks, and writes episode
  rows down as history. A tick that can't reach herdr broadcasts an empty
  list — no chips is the honest picture when herdr is gone — and writes
  nothing, so history never records a sighting that didn't happen.

  Always running; whether chips are *shown* is the cog flag's business, not
  this process's.
  """

  use GenServer

  alias Sinkr.Herdr

  @default_interval_ms 5_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "What the last tick saw — for a LiveView mounting between ticks."
  def current(server \\ __MODULE__), do: GenServer.call(server, :current)

  @doc """
  Asks again right now — for the moment just after a tether, when waiting
  out the interval would leave a renamed workspace looking stale. A cast, so
  poking a poller that isn't running (tests) is a shrug, not a crash.
  """
  def poll_now(server \\ __MODULE__), do: GenServer.cast(server, :poll)

  @impl true
  def init(opts) do
    state = %{
      lister: Keyword.get(opts, :lister, &Herdr.list_workspaces/0),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      workspaces: [],
      timer: nil
    }

    send(self(), :poll)

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state), do: {:noreply, poll(state)}

  @impl true
  def handle_cast(:poll, state), do: {:noreply, poll(state)}

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state.workspaces, state}

  defp poll(state) do
    workspaces =
      case state.lister.() do
        {:ok, workspaces} ->
          Herdr.record_workspaces(workspaces, DateTime.utc_now(:second))
          workspaces

        {:error, _reason} ->
          []
      end

    Herdr.broadcast_workspaces(workspaces)

    # Every poll re-arms the one timer, cancelling any tick already in
    # flight — a poll_now between ticks must shift the next tick, not fork
    # a second chain of them.
    if state.timer, do: Process.cancel_timer(state.timer)
    timer = Process.send_after(self(), :poll, state.interval_ms)

    %{state | workspaces: workspaces, timer: timer}
  end
end
