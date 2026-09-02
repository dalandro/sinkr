defmodule SinkrWeb.TicketLive.PresenceTest do
  @moduledoc """
  Presence chips: a workspace whose label wears a ticket's ref lights a chip
  on that ticket's row. Derived from poller broadcasts at render — presence
  is a fact about right now, so it is never stored and never touches status.
  """

  # async: false — some tests start a named poller that shares this sandbox.
  use SinkrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sinkr.Herdr
  alias Sinkr.Tickets
  alias Sinkr.Tickets.Ticket

  setup do
    {:ok, ticket} = Tickets.create_ticket(%{title: "Fix the comments composer", category: :bug})

    %{ticket: ticket, ref: Ticket.display_ref(ticket)}
  end

  defp workspace(ref, status \\ :working) do
    %{workspace_id: "w-#{ref}", label: "#{ref}-fix", agent_status: status}
  end

  test "a workspace wearing the ticket's ref lights a chip on its row",
       %{conn: conn, ticket: ticket, ref: ref} do
    {:ok, live, _html} = live(conn, ~p"/")

    Herdr.broadcast_workspaces([workspace(ref)])
    render(live)

    assert has_element?(live, "#ticket-#{ticket.id} [data-role=presence]", "working")
  end

  test "no workspace, no chip", %{conn: conn, ticket: ticket} do
    {:ok, live, _html} = live(conn, ~p"/")

    Herdr.broadcast_workspaces([
      %{workspace_id: "w9", label: "hooks-refactor", agent_status: :working}
    ])

    render(live)

    refute has_element?(live, "#ticket-#{ticket.id} [data-role=presence]")
  end

  test "presence never touches ticket status", %{conn: conn, ticket: ticket, ref: ref} do
    {:ok, live, _html} = live(conn, ~p"/")

    Herdr.broadcast_workspaces([workspace(ref)])
    render(live)

    assert Tickets.get_ticket_by_ref!(ref).status == ticket.status
  end

  test "a workspace closing takes its chip with it", %{conn: conn, ticket: ticket, ref: ref} do
    {:ok, live, _html} = live(conn, ~p"/")

    Herdr.broadcast_workspaces([workspace(ref)])
    render(live)
    Herdr.broadcast_workspaces([])
    render(live)

    refute has_element?(live, "#ticket-#{ticket.id} [data-role=presence]")
  end

  test "mounting between ticks picks up what the poller already saw",
       %{conn: conn, ticket: ticket, ref: ref} do
    start_supervised!(
      {Sinkr.Herdr.Poller, lister: fn -> {:ok, [workspace(ref)]} end, name: Sinkr.Herdr.Poller}
    )

    {:ok, live, _html} = live(conn, ~p"/")

    assert has_element?(live, "#ticket-#{ticket.id} [data-role=presence]", "working")
  end

  describe "the herdr cog flag" do
    test "hides chips without stopping the ears", %{conn: conn, ticket: ticket, ref: ref} do
      {:ok, live, _html} =
        conn
        |> put_connect_params(%{"flags" => %{"herdr" => "false"}})
        |> live(~p"/")

      Herdr.broadcast_workspaces([workspace(ref)])
      render(live)

      refute has_element?(live, "#ticket-#{ticket.id} [data-role=presence]")

      live
      |> element("#cog-menu button[phx-value-flag=herdr][phx-value-to=true]")
      |> render_click()

      assert has_element?(live, "#ticket-#{ticket.id} [data-role=presence]", "working")
    end
  end
end
