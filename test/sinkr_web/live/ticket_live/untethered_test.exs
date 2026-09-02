defmodule SinkrWeb.TicketLive.UntetheredTest do
  @moduledoc """
  The untethered strip: workspaces belonging to no ticket, shown apart from
  the ticket list with two ways out — become a ticket, or attach to one.
  Both end in a workspace rename, so the label convention stays the visible
  source of truth; the pin is only for renames herdr refuses.
  """

  # async: false — swaps the herdr CLI for a fake via the app env.
  use SinkrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sinkr.Herdr
  alias Sinkr.Tickets
  alias Sinkr.Tickets.Ticket

  defmodule AgreeableCLI do
    def rename_workspace(workspace_id, label) do
      send(Application.fetch_env!(:sinkr, :herdr_cli_test_pid), {:renamed, workspace_id, label})
      :ok
    end
  end

  defmodule RefusingCLI do
    def rename_workspace(_workspace_id, _label), do: {:error, "workspace not found"}
  end

  setup do
    Application.put_env(:sinkr, :herdr_cli_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:sinkr, :herdr_cli)
      Application.delete_env(:sinkr, :herdr_cli_test_pid)
    end)

    {:ok, ticket} = Tickets.create_ticket(%{title: "Sort the hooks out", category: :chore})

    %{ticket: ticket, ref: Ticket.display_ref(ticket)}
  end

  defp scratch, do: %{workspace_id: "w9", label: "scratch", agent_status: :idle}

  test "the strip shows untethered workspaces only", %{conn: conn, ref: ref} do
    {:ok, live, _html} = live(conn, ~p"/")

    Herdr.broadcast_workspaces([
      %{workspace_id: "w1", label: "#{ref}-fix", agent_status: :working},
      scratch()
    ])

    render(live)

    assert has_element?(live, "#untethered-strip", "scratch")
    refute has_element?(live, "#untethered-strip", "#{ref}-fix")
  end

  test "no untethered workspaces, no strip", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    Herdr.broadcast_workspaces([])
    render(live)

    refute has_element?(live, "#untethered-strip")
  end

  test "the herdr cog flag hides the strip too", %{conn: conn} do
    {:ok, live, _html} =
      conn
      |> put_connect_params(%{"flags" => %{"herdr" => "false"}})
      |> live(~p"/")

    Herdr.broadcast_workspaces([scratch()])
    render(live)

    refute has_element?(live, "#untethered-strip")
  end

  describe "attach to existing" do
    test "renames the workspace, ref up front", %{conn: conn, ref: ref} do
      Application.put_env(:sinkr, :herdr_cli, AgreeableCLI)
      {:ok, live, _html} = live(conn, ~p"/")

      Herdr.broadcast_workspaces([scratch()])
      render(live)

      live
      |> element("#tether-w9")
      |> render_submit(%{"workspace_id" => "w9", "ref" => ref})

      assert_receive {:renamed, "w9", label}
      assert label == "#{ref} scratch"
      assert render(live) =~ "Tethered."
    end

    test "a refused rename pins instead, and the pin tethers", %{
      conn: conn,
      ticket: ticket,
      ref: ref
    } do
      Application.put_env(:sinkr, :herdr_cli, RefusingCLI)
      {:ok, live, _html} = live(conn, ~p"/")

      Herdr.broadcast_workspaces([scratch()])
      render(live)

      live
      |> element("#tether-w9")
      |> render_submit(%{"workspace_id" => "w9", "ref" => ref})

      assert Herdr.pins() == %{"w9" => ticket.id}
      # The pin is a real tether: off the strip, chip on the ticket's row.
      refute has_element?(live, "#untethered-strip", "scratch")
      assert has_element?(live, "#ticket-#{ticket.id} [data-role=presence]")
      assert render(live) =~ "pinned"
    end
  end

  describe "make ticket from this" do
    test "prefills the form from the label, and saving tethers", %{conn: conn} do
      Application.put_env(:sinkr, :herdr_cli, AgreeableCLI)
      {:ok, live, _html} = live(conn, ~p"/")

      Herdr.broadcast_workspaces([scratch()])
      render(live)

      live
      |> element("#untethered-strip a", "Make ticket")
      |> render_click()

      assert has_element?(live, "#ticket-form input[name='ticket[title]'][value=scratch]")

      live
      |> form("#ticket-form", ticket: %{title: "scratch", category: "experiment"})
      |> render_submit()

      assert_receive {:renamed, "w9", label}
      new_ticket = Enum.find(Tickets.list_tickets(), &(&1.title == "scratch"))
      assert label == "#{Ticket.display_ref(new_ticket)} scratch"
    end
  end
end
