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

  @impl true
  def init(opts) do
    state = %{
      lister: Keyword.get(opts, :lister, &Herdr.list_workspaces/0),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      workspaces: []
    }

    send(self(), :poll)

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    workspaces =
      case state.lister.() do
        {:ok, workspaces} ->
          Herdr.record_workspaces(workspaces, DateTime.utc_now(:second))
          workspaces

        {:error, _reason} ->
          []
      end

    Herdr.broadcast_workspaces(workspaces)
    Process.send_after(self(), :poll, state.interval_ms)

    {:noreply, %{state | workspaces: workspaces}}
  end

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state.workspaces, state}
end
