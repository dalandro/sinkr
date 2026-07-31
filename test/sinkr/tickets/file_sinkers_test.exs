defmodule Sinkr.Tickets.FileSinkersTest do
  @moduledoc """
  The file half of `Sinkr.Tickets` — attaching, pinning and letting go.

  Split out from `Sinkr.TicketsTest` because every test here needs a scratch
  directory and its own snapshot store, which the ticket CRUD tests have no use
  for.
  """

  use Sinkr.DataCase

  # Each test gets its own store root, so the suite can never write into the
  # real one under ~/.local/share.
  @moduletag :tmp_dir

  alias Sinkr.SnapshotStore
  alias Sinkr.Tickets
  alias Sinkr.Tickets.Sinker

  setup %{tmp_dir: tmp_dir} do
    previous = Application.get_env(:sinkr, :snapshot_root)
    Application.put_env(:sinkr, :snapshot_root, Path.join(tmp_dir, "store"))
    on_exit(fn -> Application.put_env(:sinkr, :snapshot_root, previous) end)

    {:ok, ticket} = Tickets.create_ticket(%{title: "Validator rejects arrays", category: :bug})

    log = Path.join(tmp_dir, "run.log")
    File.write!(log, "boom\n")

    %{ticket: ticket, dir: tmp_dir, log: log}
  end

  describe "attach_file/2" do
    test "the file shows up on the ticket", %{ticket: ticket, log: log} do
      {:ok, _sinker} = Tickets.attach_file(ticket, log)

      assert [%Sinker{type: :file, origin: :path, value: ^log}] = Tickets.list_sinkers(ticket)
    end

    test "the path is stored resolved, so it still means the same thing later", %{
      ticket: ticket,
      dir: dir,
      log: log
    } do
      roundabout = Path.join([dir, "somewhere", "..", "run.log"])

      {:ok, sinker} = Tickets.attach_file(ticket, roundabout)

      assert sinker.value == log
    end

    test "attaching a path with nothing at it is refused as the typo it probably is", %{
      ticket: ticket,
      dir: dir
    } do
      assert {:error, :enoent} = Tickets.attach_file(ticket, Path.join(dir, "no-such.log"))
      assert Tickets.list_sinkers(ticket) == []
    end

    test "a fresh attachment is not pinned — that's a separate decision", %{
      ticket: ticket,
      log: log
    } do
      {:ok, sinker} = Tickets.attach_file(ticket, log)

      assert [%Sinker{snapshot: nil}] = Tickets.list_sinkers(ticket)
      refute sinker.id == nil
    end

    test "sinkers belong to their own ticket only", %{ticket: ticket, log: log} do
      {:ok, other} = Tickets.create_ticket(%{title: "Something else", category: :idea})
      {:ok, _} = Tickets.attach_file(ticket, log)

      assert Tickets.list_sinkers(other) == []
    end
  end

  describe "attach_upload/2" do
    test "a dropped file is copied in and pinned in one go, since there's no original to go back to",
         %{ticket: ticket, dir: dir} do
      dropped = Path.join(dir, "phx-upload-1234")
      File.write!(dropped, "png bytes")

      {:ok, _sinker} =
        Tickets.attach_upload(ticket, %{filename: "Screenshot.png", tmp_path: dropped})

      assert [%Sinker{origin: :upload, value: "Screenshot.png", snapshot: snapshot}] =
               Tickets.list_sinkers(ticket)

      assert snapshot.filename == "Screenshot.png"
      assert snapshot.mime == "image/png"
      assert File.read!(SnapshotStore.path(snapshot.sha256)) == "png bytes"
    end

    test "the copy survives the browser's temp file being swept", %{ticket: ticket, dir: dir} do
      dropped = Path.join(dir, "phx-upload-5678")
      File.write!(dropped, "png bytes")

      {:ok, _} = Tickets.attach_upload(ticket, %{filename: "Shot.png", tmp_path: dropped})
      File.rm!(dropped)

      assert [%Sinker{snapshot: snapshot}] = Tickets.list_sinkers(ticket)
      assert File.read!(SnapshotStore.path(snapshot.sha256)) == "png bytes"
    end
  end

  describe "pin_sinker/1" do
    test "keeps a copy, and records enough to serve it back", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)

      {:ok, snapshot} = Tickets.pin_sinker(sinker)

      assert snapshot.filename == "run.log"
      assert snapshot.byte_size == 5
      assert snapshot.pinned_at
      assert File.read!(SnapshotStore.path(snapshot.sha256)) == "boom\n"
    end

    test "an image records the type a preview will need to serve it", %{
      ticket: ticket,
      dir: dir
    } do
      shot = Path.join(dir, "shot.png")
      File.write!(shot, "png bytes")
      {:ok, sinker} = Tickets.attach_file(ticket, shot)

      {:ok, snapshot} = Tickets.pin_sinker(sinker)

      assert snapshot.mime == "image/png"
    end

    test "the pinned copy is what's left when the original goes", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, _} = Tickets.pin_sinker(sinker)
      File.rm!(log)

      assert [%Sinker{snapshot: snapshot} = pinned] = Tickets.list_sinkers(ticket)
      assert Tickets.file_status(pinned) == :missing
      assert File.read!(SnapshotStore.path(snapshot.sha256)) == "boom\n"
    end

    test "pinning a file that has since vanished says so", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      File.rm!(log)

      assert {:error, :enoent} = Tickets.pin_sinker(sinker)
    end

    test "pinning twice says so rather than blowing up on the unique index", %{
      ticket: ticket,
      log: log
    } do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, _} = Tickets.pin_sinker(sinker)

      assert {:error, :already_pinned} = Tickets.pin_sinker(sinker)
    end
  end

  describe "unpin_sinker/1" do
    test "the ticket stops carrying the copy", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, _} = Tickets.pin_sinker(sinker)

      {:ok, _} = Tickets.unpin_sinker(sinker)

      assert [%Sinker{snapshot: nil}] = Tickets.list_sinkers(ticket)
    end

    test "the path is still there to go back to", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, _} = Tickets.pin_sinker(sinker)

      {:ok, _} = Tickets.unpin_sinker(sinker)

      assert [%Sinker{value: ^log}] = Tickets.list_sinkers(ticket)
    end

    test "unpinning something that was never pinned says so rather than raising", %{
      ticket: ticket,
      log: log
    } do
      {:ok, sinker} = Tickets.attach_file(ticket, log)

      assert {:error, :not_pinned} = Tickets.unpin_sinker(sinker)
    end
  end

  describe "detach_sinker/1" do
    test "the file leaves the ticket", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)

      {:ok, _} = Tickets.detach_sinker(sinker)

      assert Tickets.list_sinkers(ticket) == []
    end

    test "detaching something pinned takes its snapshot row with it", %{
      ticket: ticket,
      log: log
    } do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, _} = Tickets.pin_sinker(sinker)

      {:ok, _} = Tickets.detach_sinker(sinker)

      assert Tickets.list_sinkers(ticket) == []
    end
  end

  describe "file_status/1" do
    test "a path that's still there", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)

      assert Tickets.file_status(sinker) == :on_disk
    end

    test "a path that isn't there any more", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      File.rm!(log)

      assert Tickets.file_status(sinker) == :missing
    end

    test "a dropped file is never missing, because it never had a path to be missing from", %{
      ticket: ticket,
      dir: dir
    } do
      dropped = Path.join(dir, "phx-upload-9999")
      File.write!(dropped, "bytes")
      {:ok, sinker} = Tickets.attach_upload(ticket, %{filename: "Shot.png", tmp_path: dropped})
      File.rm!(dropped)

      assert Tickets.file_status(sinker) == :upload
    end
  end

  describe "delete_ticket/1" do
    test "throwing a ticket away takes its sinkers with it", %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, _} = Tickets.pin_sinker(sinker)

      {:ok, _} = Tickets.delete_ticket(ticket)

      assert Repo.aggregate(Sinker, :count) == 0
    end
  end
end
