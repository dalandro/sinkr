defmodule SinkrWeb.TicketLive.DetailTest do
  @moduledoc """
  Inline editing on the detail pane: the fields you touch mid-flow — status,
  priority, next step — change in place. The Edit form is for the rest.
  """

  use SinkrWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Sinkr.Tickets

  setup do
    {:ok, ticket} = Tickets.create_ticket(%{title: "Fix the flaky spec", category: :bug})
    %{ticket: ticket, path: ~p"/tickets/s-#{ticket.id}"}
  end

  test "priority changes from the pane, not only the edit form", %{
    conn: conn,
    path: path,
    ticket: ticket
  } do
    {:ok, live, _html} = live(conn, path)

    html =
      live
      |> form("#quick-priority", %{"priority" => "0"})
      |> render_change()

    assert Tickets.get_ticket_by_ref!("s-#{ticket.id}").priority == 0
    assert html =~ "P0"
  end

  test "next step edits in place and sticks", %{conn: conn, path: path, ticket: ticket} do
    {:ok, live, _html} = live(conn, path)

    html =
      live
      |> form("#next-step", %{"next_step" => "Call Bob about the fixture"})
      |> render_change()

    assert Tickets.get_ticket_by_ref!("s-#{ticket.id}").next_step == "Call Bob about the fixture"
    assert html =~ "Call Bob about the fixture"
  end

  test "a ticket without a next step invites one instead of hiding the field", %{
    conn: conn,
    path: path
  } do
    {:ok, live, _html} = live(conn, path)

    assert has_element?(live, "#next-step textarea[placeholder]")
  end
end
