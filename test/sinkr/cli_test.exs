defmodule Sinkr.CLITest do
  @moduledoc """
  What you get from a terminal with no browser open, and no server necessarily
  running — the surface an agent reads when you say "see s-16, let's carry on".

  `run/1` is tested rather than `main/1`: `main/1` boots the app and halts the
  VM, neither of which a test wants, so all the behaviour lives here and the
  escript wrapper stays thin enough not to need testing.
  """

  use Sinkr.DataCase

  @moduletag :tmp_dir

  alias Sinkr.CLI
  alias Sinkr.SnapshotStore
  alias Sinkr.Tickets

  setup %{tmp_dir: tmp_dir} do
    previous = Application.get_env(:sinkr, :snapshot_root)
    Application.put_env(:sinkr, :snapshot_root, Path.join(tmp_dir, "store"))
    on_exit(fn -> Application.put_env(:sinkr, :snapshot_root, previous) end)

    {:ok, ticket} =
      Tickets.create_ticket(%{
        title: "Validator rejects arrays",
        category: :bug,
        status: :active
      })

    {:ok, _comment} = Tickets.add_comment(ticket, %{body: "make the scalar check reject arrays"})

    %{ticket: ticket, ref: "s-#{ticket.id}", dir: tmp_dir}
  end

  describe "show" do
    test "prints the ticket", %{ref: ref} do
      {:ok, output} = CLI.run(["show", ref])

      assert output =~ "# #{ref} — Validator rejects arrays"
      assert output =~ "Status: active"
      assert output =~ "make the scalar check reject arrays"
    end

    test "lists an attached file as a path you can read", %{ticket: ticket, ref: ref, dir: dir} do
      script = Path.join(dir, "validate.mjs")
      File.write!(script, "export const x = 1\n")
      {:ok, _} = Tickets.attach_file(ticket, script)

      {:ok, output} = CLI.run(["show", ref])

      assert output =~ "- #{script}"
    end

    test "a file that's gone points at the copy that survived it", %{
      ticket: ticket,
      ref: ref,
      dir: dir
    } do
      log = Path.join(dir, "run.log")
      File.write!(log, "boom\n")
      {:ok, sinker} = Tickets.attach_file(ticket, log)
      {:ok, snapshot} = Tickets.pin_sinker(sinker)
      File.rm!(log)

      {:ok, output} = CLI.run(["show", ref])

      assert output =~ "MISSING"
      assert output =~ SnapshotStore.path(snapshot.sha256)
      assert File.read!(SnapshotStore.path(snapshot.sha256)) == "boom\n"
    end

    test "a ref for no ticket fails rather than printing an empty ticket" do
      assert {:error, message} = CLI.run(["show", "s-4321"])
      assert message =~ "s-4321"
    end

    test "show with no ref says what it wanted" do
      assert {:error, message} = CLI.run(["show"])
      assert message =~ "show"
    end
  end

  describe "list" do
    test "one line per ticket, with the ref you'd pass to show", %{ref: ref} do
      {:ok, _} = Tickets.create_ticket(%{title: "Something parked", category: :idea})

      {:ok, output} = CLI.run(["list"])

      assert output =~ ref
      assert output =~ "Validator rejects arrays"
      assert output =~ "Something parked"
    end

    test "says so plainly when there's nothing to show", %{ticket: ticket} do
      {:ok, _} = Tickets.delete_ticket(ticket)

      {:ok, output} = CLI.run(["list"])

      assert output =~ "Nothing"
    end
  end

  describe "session-seen" do
    test "records the session on the workspace's episode" do
      {:ok, _output} = CLI.run(["session-seen", "w1", "aaaa-1111", "s-12-comments"])

      assert [episode] = Sinkr.Repo.all(Sinkr.Herdr.Episode)
      assert episode.workspace_id == "w1"
      assert episode.agent_session_ids == ["aaaa-1111"]
    end

    test "missing arguments print usage instead of half a row" do
      assert {:error, message} = CLI.run(["session-seen", "w1"])
      assert message =~ "Usage"
    end
  end

  describe "anything else" do
    test "no arguments at all prints usage" do
      assert {:error, message} = CLI.run([])
      assert message =~ "show"
      assert message =~ "list"
    end

    test "a command that doesn't exist prints usage" do
      assert {:error, message} = CLI.run(["pin", "s-1"])
      assert message =~ "Usage"
    end
  end
end
