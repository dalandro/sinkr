defmodule SinkrWeb.TicketLive.HistoryTest do
  @moduledoc """
  The history panel: which workspaces have ever carried this ticket, from
  episode rows — the one thing the herdr link persists, because closed
  workspaces vanish from `herdr workspace list`.
  """

  # async: false — episode writes ride the shared sandbox with the LiveView.
  use SinkrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sinkr.Herdr
  alias Sinkr.Tickets
  alias Sinkr.Tickets.Ticket

  setup do
    {:ok, ticket} = Tickets.create_ticket(%{title: "Fix the poller", category: :bug})

    %{ticket: ticket, ref: Ticket.display_ref(ticket)}
  end

  defp at(iso), do: iso |> DateTime.from_iso8601() |> then(fn {:ok, dt, 0} -> dt end)

  test "the detail pane lists every workspace this ticket has lived in",
       %{conn: conn, ref: ref} do
    Herdr.record_workspaces(
      [%{workspace_id: "w1", label: "#{ref} first-go", agent_status: :idle}],
      at("2026-09-01T09:00:00Z")
    )

    Herdr.record_workspaces(
      [%{workspace_id: "w1", label: "#{ref} first-go", agent_status: :idle}],
      at("2026-09-01T17:30:00Z")
    )

    {:ok, live, _html} = live(conn, ~p"/tickets/#{ref}")

    assert has_element?(live, "#history-section [data-role=episode]", "#{ref} first-go")
    assert has_element?(live, "#history-section", "2026-09-01 09:00")
    assert has_element?(live, "#history-section", "2026-09-01 17:30")
  end

  test "no episodes, no panel", %{conn: conn, ref: ref} do
    {:ok, live, _html} = live(conn, ~p"/tickets/#{ref}")

    refute has_element?(live, "#history-section")
  end

  test "another ticket's history stays its own", %{conn: conn, ref: ref} do
    Herdr.record_workspaces(
      [%{workspace_id: "w9", label: "s-999999 elsewhere", agent_status: :idle}],
      at("2026-09-01T09:00:00Z")
    )

    {:ok, live, _html} = live(conn, ~p"/tickets/#{ref}")

    refute has_element?(live, "#history-section")
  end

  test "a fresh sighting lands without reopening the ticket", %{conn: conn, ref: ref} do
    {:ok, live, _html} = live(conn, ~p"/tickets/#{ref}")

    workspaces = [%{workspace_id: "w1", label: "#{ref} live-now", agent_status: :working}]
    Herdr.record_workspaces(workspaces, at("2026-09-02T10:00:00Z"))
    Herdr.broadcast_workspaces(workspaces)
    render(live)

    assert has_element?(live, "#history-section [data-role=episode]", "#{ref} live-now")
  end

  test "an episode with sessions offers the freshest one to resume",
       %{conn: conn, ref: ref} do
    Herdr.record_workspaces(
      [%{workspace_id: "w1", label: "#{ref} first-go", agent_status: :idle}],
      at("2026-09-01T09:00:00Z")
    )

    Herdr.record_session("w1", "aaaa-1111", "#{ref} first-go")
    Herdr.record_session("w1", "bbbb-2222", "#{ref} first-go")

    {:ok, live, _html} = live(conn, ~p"/tickets/#{ref}")

    assert has_element?(
             live,
             "#history-section button[data-role=copy-resume][data-copy='claude --resume bbbb-2222'][phx-hook]"
           )
  end

  test "an episode that never had a session has nothing to resume", %{conn: conn, ref: ref} do
    Herdr.record_workspaces(
      [%{workspace_id: "w1", label: "#{ref} first-go", agent_status: :idle}],
      at("2026-09-01T09:00:00Z")
    )

    {:ok, live, _html} = live(conn, ~p"/tickets/#{ref}")

    refute has_element?(live, "#history-section button[data-role=copy-resume]")
  end

  test "the herdr cog flag hides history with the rest", %{conn: conn, ref: ref} do
    Herdr.record_workspaces(
      [%{workspace_id: "w1", label: "#{ref} first-go", agent_status: :idle}],
      at("2026-09-01T09:00:00Z")
    )

    {:ok, live, _html} =
      conn
      |> put_connect_params(%{"flags" => %{"herdr" => "false"}})
      |> live(~p"/tickets/#{ref}")

    refute has_element?(live, "#history-section")
  end
end
