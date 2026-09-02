defmodule Sinkr.Herdr do
  @moduledoc """
  Where herdr workspaces meet tickets.

  The link is a label convention, not a stored row: a workspace whose label
  contains a ticket ref (`s-12`) is linked to that ticket, derived fresh at
  every read from whatever the poller last saw. Rename the workspace and the
  link moves with it; nothing here to migrate or un-stick.
  """

  alias Sinkr.Herdr.Episode
  alias Sinkr.Repo
  alias Sinkr.Tickets.Ticket

  # A ref is a whole token: `s-12` in "s-12-fix" or "fix s-12", never the
  # `s-1` prefix of `s-12` (the \d+ is greedy) and never the tail of `xs-12`
  # (the boundary needs a non-word character, or nothing, before the s).
  @ref ~r/\bs-\d+/

  # The agent statuses herdr emits today. A status this app has never heard
  # of renders as idle — a new herdr version shouldn't crash the dashboard,
  # and "no chip lighting up" is the honest fallback.
  @agent_statuses %{"working" => :working, "idle" => :idle, "blocked" => :blocked}

  @doc """
  The ticket ref a workspace label carries, or nil for an untethered one.
  """
  def ticket_ref(label) do
    case Regex.run(@ref, label) do
      [ref] -> ref
      nil -> nil
    end
  end

  @doc """
  Reads `herdr workspace list` output down to the three fields the dashboard
  runs on: workspace_id, label, agent_status.

  Anything that isn't the expected envelope — the CLI missing, herdr speaking
  a different shape — is an `{:error, reason}`, so a broken herdr is a quiet
  dashboard rather than a crashed poller.
  """
  def parse_workspaces(output) do
    with {:ok, %{"result" => %{"workspaces" => workspaces}}} when is_list(workspaces) <-
           Jason.decode(output) do
      {:ok, Enum.map(workspaces, &parse_workspace/1)}
    else
      {:error, reason} -> {:error, reason}
      _other_shape -> {:error, :unexpected_shape}
    end
  end

  defp parse_workspace(%{"workspace_id" => id, "label" => label, "agent_status" => status}) do
    %{workspace_id: id, label: label, agent_status: Map.get(@agent_statuses, status, :idle)}
  end

  @herdr_topic "herdr"

  @doc "Hears every poller tick as `{:herdr_workspaces, workspaces}`."
  def subscribe, do: Phoenix.PubSub.subscribe(Sinkr.PubSub, @herdr_topic)

  @doc false
  def broadcast_workspaces(workspaces) do
    Phoenix.PubSub.broadcast(Sinkr.PubSub, @herdr_topic, {:herdr_workspaces, workspaces})
  end

  @doc """
  Asks the herdr CLI what's open right now.

  A machine without herdr on it answers `{:error, :enoent}` like any other
  broken tick — the dashboard's herdr features go quiet rather than down.
  """
  def list_workspaces do
    case System.cmd("herdr", ["workspace", "list"], stderr_to_stdout: true) do
      {output, 0} -> parse_workspaces(output)
      {output, _status} -> {:error, output}
    end
  rescue
    ErlangError -> {:error, :enoent}
  end

  @doc """
  Writes down that these workspaces were open at `seen_at`.

  One row per workspace_id for as long as it lives: the first sighting opens
  the episode, every later one moves `last_seen_at` and carries the current
  label, so a rename travels with the workspace instead of forking its
  history. `ticket_id` is deliberately not touched here — that column is a
  manual pin, and the poller has no business pinning.
  """
  def record_workspaces(workspaces, seen_at) do
    Enum.each(workspaces, fn %{workspace_id: workspace_id, label: label} ->
      Repo.insert!(
        %Episode{
          workspace_id: workspace_id,
          label: label,
          first_seen_at: seen_at,
          last_seen_at: seen_at
        },
        on_conflict: [set: [label: label, last_seen_at: seen_at]],
        conflict_target: :workspace_id
      )
    end)
  end

  @doc """
  What the poller last saw — [] when it isn't running at all, so a dashboard
  without a poller (tests, a broken boot) renders instead of crashing.
  """
  def current_workspaces do
    Sinkr.Herdr.Poller.current()
  catch
    :exit, _ -> []
  end

  @doc "Every workspace currently wearing this ticket's ref in its label."
  def workspaces_for(%Ticket{} = ticket, workspaces) do
    ref = Ticket.display_ref(ticket)

    Enum.filter(workspaces, &(ticket_ref(&1.label) == ref))
  end
end
