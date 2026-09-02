defmodule Sinkr.Herdr.PollerTest do
  @moduledoc """
  The poller is the only moving part in the herdr link: herdr has no event
  stream, so a GenServer asks on an interval and fans what it saw out over
  PubSub. Everything downstream — chips, episodes — derives from its ticks.
  """

  # async: false so the poller process shares this test's DB sandbox.
  use Sinkr.DataCase, async: false

  alias Sinkr.Herdr
  alias Sinkr.Herdr.Episode
  alias Sinkr.Herdr.Poller

  @workspaces [
    %{workspace_id: "w1", label: "s-12-comments", agent_status: :working},
    %{workspace_id: "w2", label: "hooks-refactor", agent_status: :idle}
  ]

  test "polls on start, broadcasts what it saw, and remembers it for late mounts" do
    Herdr.subscribe()

    pid = start_supervised!({Poller, lister: fn -> {:ok, @workspaces} end})

    assert_receive {:herdr_workspaces, @workspaces}
    assert Poller.current(pid) == @workspaces
    assert Repo.aggregate(Episode, :count) == 2
  end

  test "keeps polling on the interval" do
    Herdr.subscribe()

    start_supervised!({Poller, lister: fn -> {:ok, @workspaces} end, interval_ms: 10})

    assert_receive {:herdr_workspaces, _}
    assert_receive {:herdr_workspaces, _}
  end

  test "a broken herdr is a quiet dashboard, not a crash or stale chips" do
    Herdr.subscribe()

    pid = start_supervised!({Poller, lister: fn -> {:error, :enoent} end})

    assert_receive {:herdr_workspaces, []}
    assert Poller.current(pid) == []
    assert Repo.aggregate(Episode, :count) == 0
  end
end
