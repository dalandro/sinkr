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

  test "a comment can be edited in place, and then says it was", %{
    conn: conn,
    path: path,
    ticket: ticket
  } do
    {:ok, comment} = Tickets.add_comment(ticket, %{body: "Repro: open week 34 in Safri"})
    {:ok, live, html} = live(conn, path)

    refute html =~ "edited"

    live |> element("#comment-#{comment.id} button", "Edit") |> render_click()

    html =
      live
      |> form("#edit-comment-#{comment.id}", %{
        "comment" => %{"body" => "Repro: open week 34 in Safari"}
      })
      |> render_submit()

    assert [%{body: "Repro: open week 34 in Safari"}] = Tickets.list_comments(ticket)
    assert html =~ "Repro: open week 34 in Safari"
    assert html =~ "edited"
    assert html =~ "Saved."
    refute has_element?(live, "#edit-comment-#{comment.id}")
  end

  test "editing a comment can be backed out of", %{conn: conn, path: path, ticket: ticket} do
    {:ok, comment} = Tickets.add_comment(ticket, %{body: "leave me be"})
    {:ok, live, _html} = live(conn, path)

    live |> element("#comment-#{comment.id} button", "Edit") |> render_click()
    assert has_element?(live, "#edit-comment-#{comment.id}")

    live |> element("#edit-comment-#{comment.id} button", "Cancel") |> render_click()

    refute has_element?(live, "#edit-comment-#{comment.id}")
    assert [%{body: "leave me be", edited_at: nil}] = Tickets.list_comments(ticket)
  end

  # The composer's textarea is keyed by ticket and by a version that moves on
  # every landed comment: a new key means a new DOM node, which is what
  # actually empties the box (a textarea rendering "" both times never
  # re-patches) and what keeps a half-typed draft from following you to the
  # next ticket.
  test "the composer empties after a comment lands and doesn't follow you between tickets", %{
    conn: conn,
    path: path,
    ticket: ticket
  } do
    {:ok, other} = Tickets.create_ticket(%{title: "The other one", category: :chore})
    {:ok, live, html} = live(conn, path)

    [before_key] = Regex.run(~r/new-comment-body-[\w-]+/, html)
    assert before_key =~ "-#{ticket.id}-"

    html =
      live
      |> form("#new-comment", %{"comment" => %{"body" => "note to self"}})
      |> render_submit()

    [after_key] = Regex.run(~r/new-comment-body-[\w-]+/, html)
    assert after_key != before_key

    html = render_patch(live, ~p"/tickets/s-#{other.id}")
    [other_key] = Regex.run(~r/new-comment-body-[\w-]+/, html)
    assert other_key =~ "-#{other.id}-"
    assert other_key != after_key
  end

  test "ctrl+enter submits from the keyboard: both comment boxes carry the hook", %{
    conn: conn,
    path: path,
    ticket: ticket
  } do
    {:ok, comment} = Tickets.add_comment(ticket, %{body: "hookable"})
    {:ok, live, _html} = live(conn, path)

    assert has_element?(live, "#new-comment textarea[phx-hook]")

    live |> element("#comment-#{comment.id} button", "Edit") |> render_click()

    assert has_element?(live, "#edit-comment-#{comment.id} textarea[phx-hook]")
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
