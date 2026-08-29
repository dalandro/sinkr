defmodule SinkrWeb.TicketLive.DetailTest do
  @moduledoc """
  Inline editing on the detail pane: the fields you touch mid-flow — status,
  priority, comments — change in place. The Edit form is for the rest.
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

  test "a comment left on the pane lands at the top of the log and sticks", %{
    conn: conn,
    path: path,
    ticket: ticket
  } do
    {:ok, _} = Tickets.add_comment(ticket, %{body: "Repro: open week 34 in Safari"})
    {:ok, live, _html} = live(conn, path)

    html =
      live
      |> form("#new-comment", %{"comment" => %{"body" => "Call Bob about the fixture"}})
      |> render_submit()

    assert ["Call Bob about the fixture", "Repro: open week 34 in Safari"] =
             ticket |> Tickets.list_comments() |> Enum.map(& &1.body)

    assert html =~ "Call Bob about the fixture"
    assert html =~ "Saved."
    # Newest on top: the new comment is rendered before the older one.
    {bob, _} = :binary.match(html, "Call Bob about the fixture")
    {repro, _} = :binary.match(html, "Repro: open week 34 in Safari")
    assert bob < repro
  end

  test "a comment can be taken off the ticket", %{conn: conn, path: path, ticket: ticket} do
    {:ok, comment} = Tickets.add_comment(ticket, %{body: "wrong ticket, ignore"})
    {:ok, live, _html} = live(conn, path)

    html = live |> element("#comment-#{comment.id} button", "Remove") |> render_click()

    assert Tickets.list_comments(ticket) == []
    refute html =~ "wrong ticket, ignore"
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

  test "a ticket without comments invites the first one", %{conn: conn, path: path} do
    {:ok, live, _html} = live(conn, path)

    assert has_element?(live, "#new-comment textarea[placeholder]")
  end
end
