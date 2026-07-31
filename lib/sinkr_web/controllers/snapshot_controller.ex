defmodule SinkrWeb.SnapshotController do
  @moduledoc """
  Serves the bytes of a pinned snapshot so a thumbnail can render in the
  ticket UI, even after the original file it was copied from is gone.
  """

  use SinkrWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias Sinkr.Repo
  alias Sinkr.SnapshotStore
  alias Sinkr.Tickets.Snapshot

  def show(conn, %{"sha256" => sha256}) do
    # The sha is about to be handed to SnapshotStore.path/1, which joins it
    # straight into a filesystem path. SnapshotStore itself refuses anything
    # that isn't 64 lowercase hex characters, but checking it here too means
    # a bad shape is a plain 404 instead of a raised error turning into a 500.
    if SnapshotStore.valid_sha256?(sha256) do
      serve(conn, sha256)
    else
      not_found(conn)
    end
  end

  defp serve(conn, sha256) do
    case Repo.one(from s in Snapshot, where: s.sha256 == ^sha256, limit: 1) do
      nil -> not_found(conn)
      snapshot -> send_bytes(conn, snapshot)
    end
  end

  defp send_bytes(conn, snapshot) do
    path = SnapshotStore.path(snapshot.sha256)

    if File.exists?(path) do
      conn
      |> put_resp_content_type(snapshot.mime)
      |> send_file(200, path)
    else
      not_found(conn)
    end
  end

  # Plain status + body, matching how SinkrWeb.ErrorHTML renders other 404s —
  # no template needed for a body nothing here relies on.
  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Not Found")
  end
end
