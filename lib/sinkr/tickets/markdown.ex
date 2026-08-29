defmodule Sinkr.Tickets.Markdown do
  @moduledoc """
  Renders a ticket as the plain text an agent reads over a path, not a browser.

  Strictly pure — no `Repo`, no filesystem, no clock. Whether a sinker's file
  is still on disk and where its pinned copy lives are facts about the world
  right now, so the caller (`Sinkr.Tickets.file_entries/1` today; the CLI, a
  future `.md` route, and a future MCP tool tomorrow) computes them and hands
  them in as plain data. That's what makes this testable with no fixtures on
  disk, and what keeps every consumer rendering identically.
  """

  alias Sinkr.Tickets.Comment
  alias Sinkr.Tickets.Sinker
  alias Sinkr.Tickets.Ticket

  @doc """
  Turns a ticket, its comments, and its file entries into markdown — in that
  order, which is also the order the arguments come in.

  Comments arrive newest first (`Sinkr.Tickets.list_comments/1`) and are
  printed that way: the top line is where you left off. Each entry is
  `%{sinker:, status:, snapshot_path:}` — see `Sinkr.Tickets.file_entries/1`
  for how those are built. The one property worth protecting: every file
  line ends in a path something can `Read`, even the lines for a file
  that's gone.
  """
  def render(%Ticket{} = ticket, comments, entries) do
    [header(ticket), fields(ticket), comments(comments), files(entries)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp header(ticket), do: "# #{Ticket.display_ref(ticket)} — #{ticket.title}"

  defp fields(ticket) do
    "Status: #{ticket.status} · Category: #{ticket.category} · " <>
      "Priority: #{Ticket.priority_label(ticket.priority)} (P#{ticket.priority})"
  end

  # No heading for an empty list, same precedent as `Tickets.group_by_status/1`
  # — an empty section is noise, not information. Same rule for files below.
  defp comments([]), do: nil

  defp comments(comments) do
    Enum.join(["## Comments\n" | Enum.map(comments, &comment_line/1)], "\n")
  end

  defp comment_line(%Comment{body: body} = comment), do: "- #{Comment.stamp(comment)} — #{body}"

  defp files([]), do: nil

  defp files(entries) do
    Enum.join(["## Files\n" | Enum.map(entries, &file_line/1)], "\n")
  end

  defp file_line(%{sinker: sinker, status: status, snapshot_path: snapshot_path}) do
    "- " <> name(sinker) <> suffix(status, snapshot_path)
  end

  # A dropped upload has no directory to shorten — display_name/1 already
  # gives back the bare filename it arrived with. A path sinker keeps its
  # full path, since that's the thing an agent will actually go read.
  defp name(%Sinker{origin: :upload} = sinker), do: Sinker.display_name(sinker)
  defp name(%Sinker{origin: :path, value: value}), do: value

  defp suffix(:missing, nil), do: " — MISSING; no copy was kept"
  defp suffix(:missing, snapshot_path), do: " — MISSING; pinned copy: #{snapshot_path}"
  defp suffix(_status, nil), do: ""
  defp suffix(_status, snapshot_path), do: " — pinned copy: #{snapshot_path}"
end
