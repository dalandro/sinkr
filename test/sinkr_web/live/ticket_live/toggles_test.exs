defmodule SinkrWeb.TicketLive.TogglesTest do
  @moduledoc """
  The cog menu: view preferences the browser remembers, none of them data.

  Layout and show-done round-trip through the server (they change what is
  rendered); density and thumbnails never leave the client, so all the server
  owes them is the buttons. Preferences arrive as connect params — a fresh
  mount with none gets the defaults.
  """

  use SinkrWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Sinkr.Tickets

  setup do
    {:ok, urgent} = Tickets.create_ticket(%{title: "Fix the flaky spec", category: :bug})
    {:ok, urgent} = Tickets.update_ticket(urgent, %{status: :active, priority: 0})

    {:ok, shipped} = Tickets.create_ticket(%{title: "Ship the report", category: :chore})
    {:ok, shipped} = Tickets.update_ticket(shipped, %{status: :done})

    %{urgent: urgent, shipped: shipped}
  end

  describe "defaults" do
    test "grouped by status, done included", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")
      html = render(live)

      assert has_element?(live, "h2", "Active")
      assert has_element?(live, "h2", "Done")
      assert html =~ "Ship the report"
    end
  end

  describe "remembered preferences" do
    test "flat layout drops the status groupings", %{conn: conn} do
      {:ok, live, _html} =
        conn
        |> put_connect_params(%{"flags" => %{"layout" => "flat"}})
        |> live(~p"/")

      html = render(live)

      refute has_element?(live, "h2", "Active")
      refute has_element?(live, "h2", "Done")
      assert html =~ "Fix the flaky spec"
      assert html =~ "Ship the report"
    end

    test "hiding done tickets leaves the rest", %{conn: conn} do
      {:ok, live, _html} =
        conn
        |> put_connect_params(%{"flags" => %{"show_done" => "false"}})
        |> live(~p"/")

      html = render(live)

      refute html =~ "Ship the report"
      assert html =~ "Fix the flaky spec"
    end

    test "junk flags mean the defaults, not a crash", %{conn: conn} do
      {:ok, live, _html} =
        conn
        |> put_connect_params(%{"flags" => %{"layout" => "cursed", "show_done" => 42}})
        |> live(~p"/")

      assert has_element?(live, "h2", "Active")
      assert has_element?(live, "h2", "Done")
    end
  end

  describe "the cog" do
    test "switching to flat re-renders the list live", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      live
      |> element("#cog-menu button[phx-value-flag=layout][phx-value-to=flat]")
      |> render_click()

      refute has_element?(live, "h2", "Active")
      assert render(live) =~ "Fix the flaky spec"
    end

    test "hiding done live takes effect without a reload", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      html =
        live
        |> element("#cog-menu button[phx-value-flag=show_done][phx-value-to=false]")
        |> render_click()

      refute html =~ "Ship the report"
    end

    test "density and thumbnails are client-side buttons, not server events", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#cog-menu button[data-flag=density]")
      assert has_element?(live, "#cog-menu button[data-flag=thumbs]")
      refute has_element?(live, "#cog-menu button[data-flag=density][phx-value-flag]")
    end
  end
end
