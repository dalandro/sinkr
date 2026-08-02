defmodule Sinkr.Tickets do
  @moduledoc """
  Your loose ends.
  """

  import Ecto.Query, only: [from: 2]

  alias Sinkr.Repo
  alias Sinkr.SnapshotStore
  alias Sinkr.Tickets.Sinker
  alias Sinkr.Tickets.Snapshot
  alias Sinkr.Tickets.Ticket

  @doc "Every ticket, newest first."
  def list_tickets do
    Repo.all(from t in Ticket, order_by: [desc: t.inserted_at, desc: t.id])
  end

  @doc """
  Finds the ticket a `s-12` style ref names.

  Anything that isn't a ref for a real ticket — a typo, a stale bookmark —
  raises `Ecto.NoResultsError`, the same as an id that doesn't exist, so
  callers have one failure to handle rather than two.
  """
  def get_ticket_by_ref!(ref) do
    case Integer.parse(String.trim_leading(ref, "s-")) do
      {id, ""} -> Repo.get!(Ticket, id)
      _ -> raise Ecto.NoResultsError, queryable: Ticket
    end
  end

  @doc "Opens a new ticket. It starts queued; you move it from there yourself."
  def create_ticket(attrs) do
    %Ticket{}
    |> Ticket.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Edits a ticket. Status moves only ever come through here, from you."
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.changeset(attrs)
    |> Repo.update()
  end

  @doc "Throws a ticket away for good."
  def delete_ticket(%Ticket{} = ticket), do: Repo.delete(ticket)

  @doc "A blank changeset for the ticket form to render from."
  def change_ticket(%Ticket{} = ticket, attrs \\ %{}), do: Ticket.changeset(ticket, attrs)

  @doc """
  Buckets tickets by status, in the order statuses are listed to you.

  Within a bucket the most pressing ticket comes first — priority 0 is the
  drop-everything end of the scale. Statuses nothing is sitting in are left out
  entirely, so the list never shows an empty heading.
  """
  def group_by_status(tickets) do
    by_status = Enum.group_by(tickets, & &1.status)

    Ticket.statuses()
    |> Enum.map(&{&1, by_status |> Map.get(&1, []) |> Enum.sort_by(fn t -> t.priority end)})
    |> Enum.reject(fn {_status, tickets} -> tickets == [] end)
  end

  @doc "Sorts tickets flat, most pressing first, ties broken by status order."
  def sort_by_priority(tickets) do
    status_index = Ticket.statuses() |> Enum.with_index() |> Map.new()

    Enum.sort_by(tickets, fn t -> {t.priority, Map.fetch!(status_index, t.status)} end)
  end

  @doc """
  Points the ticket at a file already sitting on disk.

  The path is expanded here — `~` and `..` settled once, at attach time — so
  what's stored means the same thing later regardless of the directory this
  was called from. Refuses a path with nothing at it: that's not a file gone
  missing later (which is expected, and renders as `missing`), that's a typo
  worth catching right now.
  """
  def attach_file(%Ticket{} = ticket, path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      %Sinker{ticket_id: ticket.id}
      |> Sinker.changeset(%{type: :file, origin: :path, value: expanded})
      |> Repo.insert()
    else
      {:error, :enoent}
    end
  end

  @doc """
  Copies a dropped file straight into the ticket, pinned on the spot.

  A path sinker can be pinned or not — that's a separate decision, made
  later. An upload doesn't get that choice: the browser's temp file is swept
  soon after the request ends, so there is no "value" left to pin later. This
  stores the bytes and inserts the sinker in one call, because an upload with
  no copy would be a record of nothing.
  """
  def attach_upload(%Ticket{} = ticket, %{filename: filename, tmp_path: tmp_path}) do
    {:ok, sinker} =
      %Sinker{ticket_id: ticket.id}
      |> Sinker.changeset(%{type: :file, origin: :upload, value: filename})
      |> Repo.insert()

    {:ok, _snapshot} = insert_snapshot(sinker, tmp_path, filename)

    {:ok, sinker}
  end

  @doc """
  Takes a copy of a sinker's file right now, so the ticket keeps something
  even once the original is renamed, moved, or deleted.

  Reads from `sinker.value` at the moment you call this, so pinning a path
  that has already vanished returns `{:error, :enoent}` — same as
  `attach_file/2`, and for the same reason. An `origin: :upload` sinker will
  also hit this path, since its value is a bare filename rather than
  something on disk; that's expected, not a bug to special-case, because
  uploads are already pinned the moment they're attached.

  A sinker that's already pinned answers `{:error, :already_pinned}` rather
  than taking a second copy.
  """
  def pin_sinker(%Sinker{} = sinker) do
    if pinned?(sinker) do
      {:error, :already_pinned}
    else
      insert_snapshot(sinker, sinker.value, Path.basename(sinker.value))
    end
  end

  @doc """
  Lets go of the pinned copy. The sinker stays; only the snapshot row goes.

  The bytes themselves are left in `Sinkr.SnapshotStore`. Deleting them here
  would be wrong even though nothing about this call rules it out: content
  addressing means another sinker's snapshot may point at the very same
  bytes, and this slice keeps no reference count to know when the last
  pointer is gone. Reclaiming space is a `sinkr gc` for another day.

  Nothing pinned in the first place answers `{:error, :not_pinned}`.
  """
  def unpin_sinker(%Sinker{} = sinker) do
    case Repo.get_by(Snapshot, sinker_id: sinker.id) do
      nil -> {:error, :not_pinned}
      snapshot -> Repo.delete(snapshot)
    end
  end

  @doc "Takes a sinker off its ticket, taking any pinned snapshot with it."
  def detach_sinker(%Sinker{} = sinker), do: Repo.delete(sinker)

  @doc "Finds a sinker by id, with its snapshot preloaded."
  def get_sinker!(id), do: Repo.get!(Sinker, id) |> Repo.preload(:snapshot)

  @doc "Every sinker on a ticket, oldest first, with its snapshot preloaded."
  def list_sinkers(%Ticket{} = ticket) do
    Repo.all(
      from s in Sinker,
        where: s.ticket_id == ^ticket.id,
        order_by: [asc: s.inserted_at, asc: s.id],
        preload: :snapshot
    )
  end

  @doc """
  Builds the entry list `Sinkr.Tickets.Markdown.render/2` needs: every sinker
  on the ticket, paired with its live `file_status/1` and, when it has been
  pinned, the path its copy lives at.

  Lives here rather than in the CLI so the later `.md` route and MCP tool
  don't each reinvent this join — they call this and hand the result
  straight to `Markdown.render/2`.
  """
  def file_entries(%Ticket{} = ticket) do
    ticket
    |> list_sinkers()
    |> Enum.map(fn sinker ->
      %{
        sinker: sinker,
        status: file_status(sinker),
        snapshot_path: snapshot_path(sinker.snapshot)
      }
    end)
  end

  @doc """
  Whether a sinker's file can be read right now.

  This is never stored, only computed when you ask — the same rule this app
  already holds to for ticket status: a fact about the world right now
  doesn't belong in a column, or it would just be lying by the time anyone
  reads it back. An upload sinker answers `:upload` before touching the
  filesystem at all, since its value is a bare filename rather than a path —
  stat'ing it would only tell you about some unrelated file that happens to
  share the name in whatever directory the caller runs from.
  """
  def file_status(%Sinker{origin: :upload}), do: :upload

  def file_status(%Sinker{origin: :path, value: value}) do
    if File.exists?(value), do: :on_disk, else: :missing
  end

  defp snapshot_path(nil), do: nil
  defp snapshot_path(%Snapshot{sha256: sha256}), do: SnapshotStore.path(sha256)

  # Asked before pinning rather than letting the unique index refuse the
  # insert, so a double-clicked button gets an answer instead of a 500.
  defp pinned?(sinker), do: Repo.exists?(from s in Snapshot, where: s.sinker_id == ^sinker.id)

  # Shared by attach_upload/2 (source is the browser's temp file) and
  # pin_sinker/1 (source is the sinker's own value) — both end the same way,
  # copying bytes into the store and recording enough to serve them back.
  defp insert_snapshot(sinker, source_path, filename) do
    with {:ok, %{sha256: sha256, byte_size: byte_size}} <- SnapshotStore.put(source_path) do
      %Snapshot{sinker_id: sinker.id}
      |> Snapshot.changeset(%{
        sha256: sha256,
        filename: filename,
        mime: MIME.from_path(filename),
        byte_size: byte_size,
        pinned_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()
    end
  end
end
