defmodule Sinkr.Herdr.EpisodesTest do
  @moduledoc """
  Episodes are the only persistence in the herdr link: one row per workspace
  the poller ever sees, kept because closed workspaces vanish from
  `herdr workspace list` and history can't be backfilled later.
  """

  use Sinkr.DataCase, async: true

  alias Sinkr.Herdr
  alias Sinkr.Herdr.Episode

  defp workspace(attrs) do
    Map.merge(%{workspace_id: "w1", label: "s-12-comments", agent_status: :working}, attrs)
  end

  defp at(iso), do: iso |> DateTime.from_iso8601() |> then(fn {:ok, dt, 0} -> dt end)

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
