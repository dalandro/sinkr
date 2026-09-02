defmodule Sinkr.HerdrTest do
  @moduledoc """
  The herdr link, derived at read: a workspace whose label contains a ticket
  ref (`s-12`) is linked to that ticket. Nothing here writes anything.
  """

  use ExUnit.Case, async: true

  alias Sinkr.Herdr

  describe "ticket_ref/1" do
    test "finds the ref anywhere in a label" do
      assert Herdr.ticket_ref("s-12") == "s-12"
      assert Herdr.ticket_ref("s-12-comments-fix") == "s-12"
      assert Herdr.ticket_ref("fix comments s-12") == "s-12"
    end

    test "a label without a ref is untethered" do
      assert Herdr.ticket_ref("hooks-refactor") == nil
      assert Herdr.ticket_ref("") == nil
    end

    test "a ref is a whole token, not a prefix of a longer one" do
      # `s-1` must not claim the `s-12` workspace, and vice versa.
      assert Herdr.ticket_ref("s-12-fix") == "s-12"
      refute Herdr.ticket_ref("xs-12") == "s-12"
      assert Herdr.ticket_ref("s-1") == "s-1"
    end
  end

  describe "parse_workspaces/1" do
    # Verbatim shape from `herdr workspace list` (verified 2026-09-02),
    # trimmed to two workspaces.
    @cli_output ~s({"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[) <>
                  ~s({"active_tab_id":"w1:1","agent_status":"working","focused":false,"label":"s-12-comments","number":1,"pane_count":3,"tab_count":1,"workspace_id":"w1"},) <>
                  ~s({"active_tab_id":"w2:1","agent_status":"idle","focused":true,"label":"hooks-refactor","number":2,"pane_count":2,"tab_count":1,"workspace_id":"w2"}]}})

    test "keeps the three fields the dashboard runs on" do
      assert {:ok,
              [
                %{workspace_id: "w1", label: "s-12-comments", agent_status: :working},
                %{workspace_id: "w2", label: "hooks-refactor", agent_status: :idle}
              ]} = Herdr.parse_workspaces(@cli_output)
    end

    test "an agent_status it has never heard of degrades to idle, not a crash" do
      output =
        String.replace(@cli_output, ~s("agent_status":"working"), ~s("agent_status":"levitating"))

      assert {:ok, [%{workspace_id: "w1", agent_status: :idle} | _]} =
               Herdr.parse_workspaces(output)
    end

    test "garbage output is an error, not a crash" do
      assert {:error, _reason} = Herdr.parse_workspaces("herdr: command not found")
      assert {:error, _reason} = Herdr.parse_workspaces(~s({"id":"x","result":{}}))
    end
  end

  describe "workspaces_for/2" do
    test "matches a ticket to every workspace wearing its ref" do
      ticket = %Sinkr.Tickets.Ticket{id: 12}

      workspaces = [
        %{workspace_id: "w1", label: "s-12-comments", agent_status: :working},
        %{workspace_id: "w2", label: "hooks-refactor", agent_status: :idle},
        %{workspace_id: "w3", label: "s-12 retry", agent_status: :blocked},
        %{workspace_id: "w4", label: "s-1-other", agent_status: :working}
      ]

      assert [%{workspace_id: "w1"}, %{workspace_id: "w3"}] =
               Herdr.workspaces_for(ticket, workspaces)
    end
  end
end
