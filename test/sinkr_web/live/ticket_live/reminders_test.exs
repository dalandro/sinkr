defmodule SinkrWeb.TicketLive.RemindersTest do
  @moduledoc """
  The reminders strip: every scheduled nudge with when it fires, the ones
  that fired today lit up until you say you've seen them, and a fold to add
  another.
  """

  use SinkrWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Sinkr.Reminders

  test "lists reminders with their schedule", %{conn: conn} do
    {:ok, _} =
      Reminders.create_reminder(%{
        title: "Run npx",
        cadence: :weekly,
        weekday: 5,
        time: ~T[09:00:00]
      })

    {:ok, live, _html} = live(conn, ~p"/")

    assert has_element?(live, "#reminders-strip", "Run npx")
    assert has_element?(live, "#reminders-strip", "Fri 09:00")
  end

  test "adds a reminder from the fold", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    live
    |> form("#reminder-form", %{
      "reminder" => %{"title" => "Check Linear inbox", "cadence" => "daily", "time" => "09:00"}
    })
    |> render_submit()

    assert has_element?(live, "#reminders-strip", "Check Linear inbox")
    assert has_element?(live, "#reminders-strip", "daily 09:00")
  end

  test "a blank title is refused", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html =
      live
      |> form("#reminder-form", %{
        "reminder" => %{"title" => "", "cadence" => "daily", "time" => "09:00"}
      })
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "a ring lights the reminder up until acknowledged", %{conn: conn} do
    {:ok, reminder} =
      Reminders.create_reminder(%{title: "Run npx", cadence: :daily, time: ~T[00:00:00]})

    {:ok, live, _html} = live(conn, ~p"/")
    refute has_element?(live, "#reminder-#{reminder.id}[data-ringing]")

    Reminders.fire_due(Reminders.local_now())
    render(live)
    assert has_element?(live, "#reminder-#{reminder.id}[data-ringing]")

    live |> element("#reminder-#{reminder.id} button", "Done") |> render_click()
    refute has_element?(live, "#reminder-#{reminder.id}[data-ringing]")
  end

  test "removes a reminder", %{conn: conn} do
    {:ok, reminder} =
      Reminders.create_reminder(%{title: "Run npx", cadence: :daily, time: ~T[09:00:00]})

    {:ok, live, _html} = live(conn, ~p"/")

    live |> element("#reminder-#{reminder.id} button", "Remove") |> render_click()

    refute has_element?(live, "#reminder-#{reminder.id}")
  end
end
