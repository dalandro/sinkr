defmodule SinkrWeb.SnapshotControllerTest do
  @moduledoc """
  Serves the bytes of a pinned copy so a thumbnail can render.

  The sha in the URL is joined into a filesystem path, so the tests that matter
  most here are the ones that hand it something that isn't a sha.
  """

  use SinkrWeb.ConnCase

  @moduletag :tmp_dir

  alias Sinkr.SnapshotStore
  alias Sinkr.Tickets

  setup %{tmp_dir: tmp_dir} do
    previous = Application.get_env(:sinkr, :snapshot_root)
    Application.put_env(:sinkr, :snapshot_root, Path.join(tmp_dir, "store"))
    on_exit(fn -> Application.put_env(:sinkr, :snapshot_root, previous) end)

    {:ok, ticket} = Tickets.create_ticket(%{title: "Planner won't load", category: :bug})

    shot = Path.join(tmp_dir, "shot.png")
    File.write!(shot, "png bytes")
    {:ok, sinker} = Tickets.attach_file(ticket, shot)
    {:ok, snapshot} = Tickets.pin_sinker(sinker)

    %{snapshot: snapshot, original: shot}
  end

  describe "GET /snapshots/:sha256" do
    test "serves the pinned bytes", %{conn: conn, snapshot: snapshot} do
      conn = get(conn, ~p"/snapshots/#{snapshot.sha256}")

      assert conn.status == 200
      assert conn.resp_body == "png bytes"
    end

    test "says what kind of file it is, so a browser will render it", %{
      conn: conn,
      snapshot: snapshot
    } do
      conn = get(conn, ~p"/snapshots/#{snapshot.sha256}")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "image/png"
    end

    test "still serves it once the original is deleted — the whole point of pinning", %{
      conn: conn,
      snapshot: snapshot,
      original: original
    } do
      File.rm!(original)

      conn = get(conn, ~p"/snapshots/#{snapshot.sha256}")

      assert conn.status == 200
      assert conn.resp_body == "png bytes"
    end

    test "a hash nothing is stored under is a 404, not a crash", %{conn: conn} do
      conn = get(conn, ~p"/snapshots/#{String.duplicate("a", 64)}")

      assert conn.status == 404
    end

    test "anything that isn't a sha is refused before it reaches the filesystem", %{conn: conn} do
      # One URL segment each, so the router matches and the controller is the
      # thing being tested — a multi-segment path would never reach it.
      for not_a_sha <- ["..", "short", String.duplicate("A", 64), String.duplicate("z", 64)] do
        conn = get(conn, "/snapshots/#{not_a_sha}")

        assert conn.status == 404, "#{not_a_sha} was not refused"
      end
    end

    test "the snapshot bytes on disk are what's being served", %{snapshot: snapshot} do
      assert File.read!(SnapshotStore.path(snapshot.sha256)) == "png bytes"
    end
  end
end
