defmodule Sinkr.Herdr.TetherTest do
  @moduledoc """
  Tethering an untethered workspace: rename it so the label convention stays
  the visible source of truth, and only when herdr refuses fall back to
  pinning its episode row.
  """

  # async: false — swaps the herdr CLI for a fake via the app env.
  use Sinkr.DataCase, async: false

  alias Sinkr.Herdr
  alias Sinkr.Herdr.Episode
  alias Sinkr.Tickets

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

    %{
      ticket: ticket,
      workspace: %{workspace_id: "w2", label: "hooks-refactor", agent_status: :idle}
    }
  end

  test "renames the workspace with the ref up front", %{ticket: ticket, workspace: workspace} do
    Application.put_env(:sinkr, :herdr_cli, AgreeableCLI)

    assert {:ok, :renamed} = Herdr.tether(ticket, workspace)
    assert_receive {:renamed, "w2", label}
    assert label == "s-#{ticket.id} hooks-refactor"
    assert Herdr.pins() == %{}
  end

  test "a refused rename falls back to pinning the episode",
       %{ticket: ticket, workspace: workspace} do
    Application.put_env(:sinkr, :herdr_cli, RefusingCLI)
    Herdr.record_workspaces([workspace], DateTime.utc_now(:second))

    assert {:ok, :pinned} = Herdr.tether(ticket, workspace)
    assert [%Episode{workspace_id: "w2", ticket_id: ticket_id}] = Repo.all(Episode)
    assert ticket_id == ticket.id
    assert Herdr.pins() == %{"w2" => ticket.id}
  end

  test "pinning a workspace the poller hasn't logged yet still sticks",
       %{ticket: ticket, workspace: workspace} do
    # Shouldn't happen — the strip only shows what the poller saw — but a
    # tick racing a close is cheap to survive.
    Application.put_env(:sinkr, :herdr_cli, RefusingCLI)

    assert {:ok, :pinned} = Herdr.tether(ticket, workspace)
    assert [%Episode{workspace_id: "w2"}] = Repo.all(Episode)
  end

  test "pins/0 ignores unpinned episodes", %{workspace: workspace} do
    Herdr.record_workspaces([workspace], DateTime.utc_now(:second))

    assert Herdr.pins() == %{}
  end
end
