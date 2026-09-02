defmodule Sinkr.Herdr do
  @moduledoc """
  Where herdr workspaces meet tickets.

  The link is a label convention, not a stored row: a workspace whose label
  contains a ticket ref (`s-12`) is linked to that ticket, derived fresh at
  every read from whatever the poller last saw. Rename the workspace and the
  link moves with it; nothing here to migrate or un-stick.
  """

  import Ecto.Query, only: [from: 2]

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

  @doc "Asks the herdr CLI what's open right now."
  def list_workspaces do
    with {:ok, output} <- cli().list_workspaces() do
      parse_workspaces(output)
    end
  end

  @doc """
  Ties an untethered workspace to a ticket, the way every tethered workspace
  is tied: by its label. The ref goes up front (`s-12 hooks-refactor`), so
  the convention stays the visible source of truth. Only when herdr refuses
  the rename does the episode row take a `ticket_id` pin instead — the
  fallback, never the first choice.
  """
  def tether(%Ticket{} = ticket, workspace) do
    label = "#{Ticket.display_ref(ticket)} #{workspace.label}"

    case cli().rename_workspace(workspace.workspace_id, label) do
      :ok ->
        {:ok, :renamed}

      {:error, _reason} ->
        pin(ticket, workspace)
        {:ok, :pinned}
    end
  end

  @doc """
  This ticket's workspace history, freshest sighting first: every episode
  whose stored label wears the ticket's ref, plus any pinned to it.

  The label match happens here rather than in SQL so `ticket_ref/1` stays
  the only place that knows what counts as a ref — a LIKE would happily let
  `s-1` claim `s-12`'s history. The table is one row per workspace ever
  seen on one person's machine; reading all of it is nothing.
  """
  def episodes_for(%Ticket{} = ticket) do
    ref = Ticket.display_ref(ticket)

    Repo.all(from e in Episode, order_by: [desc: e.last_seen_at, desc: e.id])
    |> Enum.filter(&(ticket_ref(&1.label) == ref or &1.ticket_id == ticket.id))
  end

  @doc "Every pin, as `workspace_id => ticket_id` — the shape the joins take."
  def pins do
    Repo.all(from e in Episode, where: not is_nil(e.ticket_id))
    |> Map.new(&{&1.workspace_id, &1.ticket_id})
  end

  # The workspace is on screen, so the poller has all but certainly logged
  # it already — but a tick racing a close is cheap to survive, so this
  # upserts rather than trusting the row is there.
  defp pin(ticket, %{workspace_id: workspace_id, label: label}) do
    now = DateTime.utc_now(:second)

    Repo.insert!(
      %Episode{
        workspace_id: workspace_id,
        label: label,
        first_seen_at: now,
        last_seen_at: now,
        ticket_id: ticket.id
      },
      on_conflict: [set: [ticket_id: ticket.id]],
      conflict_target: :workspace_id
    )
  end

  defp cli, do: Application.get_env(:sinkr, :herdr_cli, Sinkr.Herdr.CLI)

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

  @doc "Nudges the poller to ask herdr again right now, if one is running."
  def poll_now, do: Sinkr.Herdr.Poller.poll_now()

  @doc """
  Every workspace currently tethered to this ticket: wearing its ref in the
  label, or pinned to it — the fallback for a workspace whose rename was
  refused. `pins` is `workspace_id => ticket_id`, from `pins/0`.
  """
  def workspaces_for(%Ticket{} = ticket, workspaces, pins \\ %{}) do
    ref = Ticket.display_ref(ticket)

    Enum.filter(workspaces, fn workspace ->
      ticket_ref(workspace.label) == ref or pins[workspace.workspace_id] == ticket.id
    end)
  end

  @doc "Workspaces belonging to no ticket at all — no ref in the label, no pin."
  def untethered(workspaces, pins) do
    Enum.filter(workspaces, fn workspace ->
      is_nil(ticket_ref(workspace.label)) and not Map.has_key?(pins, workspace.workspace_id)
    end)
  end
end
