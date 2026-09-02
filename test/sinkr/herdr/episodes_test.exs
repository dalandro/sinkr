defmodule Sinkr.Herdr.EpisodesTest do
  @moduledoc """
  Episodes are the only persistence in the herdr link: one row per workspace
  the poller ever sees, kept because closed workspaces vanish from
  `herdr workspace list` and history can't be backfilled later.
  """

  use Sinkr.DataCase, async: false

  alias Sinkr.Herdr
  alias Sinkr.Herdr.Episode

  defp workspace(attrs) do
    Map.merge(%{workspace_id: "w1", label: "s-12-comments", agent_status: :working}, attrs)
  end

  defp at(iso), do: iso |> DateTime.from_iso8601() |> then(fn {:ok, dt, 0} -> dt end)

  describe "episodes_for/1" do
    setup do
      {:ok, ticket} = Sinkr.Tickets.create_ticket(%{title: "Fix it", category: :bug})
      %{ticket: ticket, ref: Sinkr.Tickets.Ticket.display_ref(ticket)}
    end

    test "finds every episode whose stored label wears the ref", %{ticket: ticket, ref: ref} do
      Herdr.record_workspaces(
        [
          workspace(%{workspace_id: "w1", label: "#{ref}-fix"}),
          workspace(%{workspace_id: "w2", label: "hooks-refactor"}),
          workspace(%{workspace_id: "w3", label: "#{ref} retry"})
        ],
        at("2026-09-02T10:00:00Z")
      )

      assert [%Episode{workspace_id: _}, %Episode{}] = episodes = Herdr.episodes_for(ticket)
      assert Enum.map(episodes, & &1.workspace_id) |> Enum.sort() == ["w1", "w3"]
    end

    test "a pinned episode belongs whatever its label says", %{ticket: ticket} do
      Herdr.record_workspaces([workspace(%{label: "scratch"})], at("2026-09-02T10:00:00Z"))

      {:ok, :pinned} = tethered_by_pin(ticket, workspace(%{label: "scratch"}))

      assert [%Episode{workspace_id: "w1"}] = Herdr.episodes_for(ticket)
    end

    test "the freshest sighting comes first", %{ref: ref} do
      Herdr.record_workspaces(
        [workspace(%{workspace_id: "w1", label: "#{ref} old"})],
        at("2026-09-02T09:00:00Z")
      )

      Herdr.record_workspaces(
        [workspace(%{workspace_id: "w2", label: "#{ref} new"})],
        at("2026-09-02T10:00:00Z")
      )

      {:ok, ticket} = {:ok, %Sinkr.Tickets.Ticket{id: ref_id(ref)}}

      assert ["w2", "w1"] = Herdr.episodes_for(ticket) |> Enum.map(& &1.workspace_id)
    end

    defp ref_id(ref), do: ref |> String.trim_leading("s-") |> String.to_integer()

    defp tethered_by_pin(ticket, workspace) do
      Application.put_env(:sinkr, :herdr_cli, __MODULE__.RefusingCLI)
      on_exit(fn -> Application.delete_env(:sinkr, :herdr_cli) end)

      Herdr.tether(ticket, workspace)
    end
  end

  defmodule RefusingCLI do
    def rename_workspace(_workspace_id, _label), do: {:error, "workspace not found"}
  end

  describe "record_session/3" do
    test "lands on the workspace's episode, oldest first" do
      Herdr.record_workspaces([workspace(%{})], at("2026-09-02T10:00:00Z"))

      Herdr.record_session("w1", "aaaa-1111", "s-12-comments")
      Herdr.record_session("w1", "bbbb-2222", "s-12-comments")

      assert [%Episode{agent_session_ids: ["aaaa-1111", "bbbb-2222"]}] = Repo.all(Episode)
    end

    test "the same session starting twice is one entry" do
      Herdr.record_workspaces([workspace(%{})], at("2026-09-02T10:00:00Z"))

      Herdr.record_session("w1", "aaaa-1111", "s-12-comments")
      Herdr.record_session("w1", "aaaa-1111", "s-12-comments")

      assert [%Episode{agent_session_ids: ["aaaa-1111"]}] = Repo.all(Episode)
    end

    test "a session in a workspace the poller hasn't logged yet opens the episode" do
      # The hook can fire before the first tick ever sees the workspace.
      Herdr.record_session("w7", "cccc-3333", "s-9 fresh")

      assert [%Episode{workspace_id: "w7", label: "s-9 fresh", agent_session_ids: ["cccc-3333"]}] =
               Repo.all(Episode)
    end
  end

  describe "record_workspaces/2" do
    test "a first sighting opens the episode" do
      seen = at("2026-09-02T10:00:00Z")

      Herdr.record_workspaces([workspace(%{})], seen)

      assert [%Episode{workspace_id: "w1", label: "s-12-comments"} = episode] = Repo.all(Episode)
      assert episode.first_seen_at == seen
      assert episode.last_seen_at == seen
      assert episode.ticket_id == nil
    end

    test "a later sighting only moves last_seen_at" do
      Herdr.record_workspaces([workspace(%{})], at("2026-09-02T10:00:00Z"))
      Herdr.record_workspaces([workspace(%{})], at("2026-09-02T10:00:05Z"))

      assert [episode] = Repo.all(Episode)
      assert episode.first_seen_at == at("2026-09-02T10:00:00Z")
      assert episode.last_seen_at == at("2026-09-02T10:00:05Z")
    end

    test "a rename travels with the workspace, history intact" do
      Herdr.record_workspaces([workspace(%{})], at("2026-09-02T10:00:00Z"))
      Herdr.record_workspaces([workspace(%{label: "s-12 retry"})], at("2026-09-02T10:00:05Z"))

      assert [%Episode{label: "s-12 retry"} = episode] = Repo.all(Episode)
      assert episode.first_seen_at == at("2026-09-02T10:00:00Z")
    end

    test "untethered workspaces are logged too" do
      Herdr.record_workspaces([workspace(%{label: "hooks-refactor"})], at("2026-09-02T10:00:00Z"))

      assert [%Episode{label: "hooks-refactor", ticket_id: nil}] = Repo.all(Episode)
    end

    test "one tick can carry many workspaces" do
      Herdr.record_workspaces(
        [workspace(%{}), workspace(%{workspace_id: "w2", label: "tos"})],
        at("2026-09-02T10:00:00Z")
      )

      assert Repo.aggregate(Episode, :count) == 2
    end
  end
end
