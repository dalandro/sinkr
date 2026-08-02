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

  test "saving the edit form says so", %{conn: conn, path: path} do
    {:ok, live, _html} = live(conn, path)

    live |> element("#edit-ticket") |> render_click()

    html =
      live
      |> form("#ticket-form", %{"ticket" => %{"title" => "Fix the flaky spec properly"}})
      |> render_submit()

    assert html =~ "Saved."
  end

  test "inline edits say Saved too, and it clears itself", %{conn: conn, path: path} do
    {:ok, live, _html} = live(conn, path)

    html =
      live
      |> form("#quick-priority", %{"priority" => "1"})
      |> render_change()

    assert html =~ "Saved."

    send(live.pid, :clear_flash)
    refute render(live) =~ "Saved."
  end

  test "a ticket without a next step invites one instead of hiding the field", %{
    conn: conn,
    path: path
  } do
    {:ok, live, _html} = live(conn, path)

    assert has_element?(live, "#next-step textarea[placeholder]")
  end
end
