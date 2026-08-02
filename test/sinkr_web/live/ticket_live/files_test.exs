defmodule SinkrWeb.TicketLive.FilesTest do
  @moduledoc """
  The Files section of an open ticket: attaching a path, keeping a copy, and
  letting go of either.
  """

  use SinkrWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  alias Sinkr.Tickets

  setup %{tmp_dir: tmp_dir} do
    previous = Application.get_env(:sinkr, :snapshot_root)
    Application.put_env(:sinkr, :snapshot_root, Path.join(tmp_dir, "store"))
    on_exit(fn -> Application.put_env(:sinkr, :snapshot_root, previous) end)

    {:ok, ticket} = Tickets.create_ticket(%{title: "Validator rejects arrays", category: :bug})

    log = Path.join(tmp_dir, "run.log")
    File.write!(log, "boom\n")

    %{ticket: ticket, path: ~p"/tickets/s-#{ticket.id}", log: log, dir: tmp_dir}
  end

  describe "attaching by path" do
    test "the file appears on the ticket", %{conn: conn, path: path, log: log} do
      {:ok, live, _html} = live(conn, path)

      html =
        live
        |> form("#attach-file-form", %{"path" => log})
        |> render_submit()

      assert html =~ "run.log"
    end

    test "a path with nothing at it is reported rather than silently dropped", %{
      conn: conn,
      path: path,
      dir: dir
    } do
      {:ok, live, _html} = live(conn, path)

      html =
        live
        |> form("#attach-file-form", %{"path" => Path.join(dir, "no-such.log")})
        |> render_submit()

      assert html =~ "no-such.log" or html =~ "Nothing at that path"
      refute has_element?(live, "[data-role=sinker]")
    end

    test "a ticket with no files says so instead of showing an empty list", %{
      conn: conn,
      path: path
    } do
      {:ok, _live, html} = live(conn, path)

      assert html =~ "Files"
      refute html =~ "data-role=\"sinker\""
    end
  end

  describe "pinning" do
    setup %{ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      %{sinker: sinker}
    end

    test "an unpinned file offers to be kept", %{conn: conn, path: path, sinker: sinker} do
      {:ok, live, _html} = live(conn, path)

      assert has_element?(live, "#sinker-#{sinker.id} button[phx-click=pin]")
    end

    test "keeping a copy marks it kept", %{conn: conn, path: path, sinker: sinker} do
      {:ok, live, _html} = live(conn, path)

      html =
        live
        |> element("#sinker-#{sinker.id} button[phx-click=pin]")
        |> render_click()

      assert html =~ "pinned"
    end

    test "letting the copy go leaves the file attached", %{
      conn: conn,
      path: path,
      sinker: sinker
    } do
      {:ok, _} = Tickets.pin_sinker(sinker)
      {:ok, live, _html} = live(conn, path)

      html =
        live
        |> element("#sinker-#{sinker.id} button[phx-click=unpin]")
        |> render_click()

      refute html =~ "pinned"
      assert html =~ "run.log"
    end

    test "a file that's gone is flagged, and its copy is still offered", %{
      conn: conn,
      path: path,
      sinker: sinker,
      log: log
    } do
      {:ok, snapshot} = Tickets.pin_sinker(sinker)
      File.rm!(log)

      {:ok, _live, html} = live(conn, path)

      assert html =~ "missing"
      assert html =~ "/snapshots/#{snapshot.sha256}"
    end
  end

  describe "uploads" do
    # One file_input call per file: the test harness shares a single client
    # process across a batch, and consuming the first finished entry (as a
    # real browser safely does — each entry has its own channel) tears that
    # shared process down under its siblings.
    test "dropped files land attached, pinned, with nothing left to click", %{
      conn: conn,
      path: path,
      ticket: ticket
    } do
      {:ok, live, _html} = live(conn, path)

      render_upload(
        file_input(live, "#upload-form", :files, [%{name: "Screenshot.png", content: "png bytes"}]),
        "Screenshot.png"
      )

      html =
        render_upload(
          file_input(live, "#upload-form", :files, [%{name: "run.log", content: "boom\n"}]),
          "run.log"
        )

      assert html =~ "Screenshot.png"
      assert html =~ "run.log"
      assert html =~ "pinned"

      sinkers = Tickets.list_sinkers(ticket)
      assert length(sinkers) == 2
      assert Enum.all?(sinkers, &(&1.origin == :upload))
      assert Enum.all?(sinkers, & &1.snapshot)
    end

    test "a dropped file can be detached but never unpinned — its copy is all there is", %{
      conn: conn,
      path: path,
      ticket: ticket,
      dir: dir
    } do
      dropped = Path.join(dir, "phx-upload-1")
      File.write!(dropped, "png bytes")

      {:ok, sinker} =
        Tickets.attach_upload(ticket, %{filename: "Screenshot.png", tmp_path: dropped})

      {:ok, live, _html} = live(conn, path)

      refute has_element?(live, "#sinker-#{sinker.id} button[phx-click=unpin]")
      refute has_element?(live, "#sinker-#{sinker.id} button[phx-click=pin]")
      assert has_element?(live, "#sinker-#{sinker.id} button[phx-click=detach]")
    end
  end

  describe "detaching" do
    test "the file leaves the ticket", %{conn: conn, path: path, ticket: ticket, log: log} do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, live, _html} = live(conn, path)

      live
      |> element("#sinker-#{sinker.id} button[phx-click=detach]")
      |> render_click()

      refute has_element?(live, "#sinker-#{sinker.id}")
      assert Tickets.list_sinkers(ticket) == []
    end
  end

  describe "previews" do
    test "a pinned image is shown, not just named", %{
      conn: conn,
      path: path,
      ticket: ticket,
      dir: dir
    } do
      shot = Path.join(dir, "shot.png")
      File.write!(shot, "png bytes")
      {:ok, sinker} = Tickets.attach_file(ticket, shot)
      {:ok, snapshot} = Tickets.pin_sinker(sinker)

      {:ok, _live, html} = live(conn, path)

      assert html =~ ~s(src="/snapshots/#{snapshot.sha256}")
    end

    test "a pinned text file is named, not shown as a broken image", %{
      conn: conn,
      path: path,
      ticket: ticket,
      log: log
    } do
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, snapshot} = Tickets.pin_sinker(sinker)

      {:ok, _live, html} = live(conn, path)

      refute html =~ ~s(<img src="/snapshots/#{snapshot.sha256}")
      assert html =~ "run.log"
    end
  end
end
