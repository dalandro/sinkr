defmodule Sinkr.Tickets.MarkdownTest do
  @moduledoc """
  This is the format an agent reads when you say "see s-16, let's carry on", so
  the thing worth protecting is that every file line ends in a path that can be
  read — including the lines where the original is gone.
  """

  # Rendering is pure: no repo, no filesystem, no clock.
  use ExUnit.Case, async: true

  alias Sinkr.Tickets.Comment
  alias Sinkr.Tickets.Markdown
  alias Sinkr.Tickets.Sinker
  alias Sinkr.Tickets.Snapshot
  alias Sinkr.Tickets.Ticket

  @ticket %Ticket{
    id: 16,
    title: "Validator rejects arrays",
    category: :bug,
    status: :active,
    priority: 1
  }

  @comments [
    %Comment{
      body: "make the scalar check reject arrays",
      inserted_at: ~U[2026-08-29 14:03:00Z]
    },
    %Comment{
      body: "repro: POST a list where the schema says string",
      inserted_at: ~U[2026-08-28 09:10:00Z]
    }
  ]

  describe "render/2" do
    test "leads with the ref and title, then the fields worth knowing" do
      assert Markdown.render(@ticket, [], []) == """
             # s-16 — Validator rejects arrays

             Status: active · Category: bug · Priority: This week (P1)
             """
    end

    test "comments come newest first, each stamped with when it was left" do
      assert Markdown.render(@ticket, @comments, []) =~ """
             ## Comments

             - 2026-08-29 14:03 — make the scalar check reject arrays
             - 2026-08-28 09:10 — repro: POST a list where the schema says string
             """
    end

    test "an edited comment says so, and when" do
      [latest | _] = @comments
      edited = %{latest | edited_at: ~U[2026-08-29 15:20:00Z]}

      assert Markdown.render(@ticket, [edited], []) =~
               "- 2026-08-29 14:03 — make the scalar check reject arrays (edited 2026-08-29 15:20)"
    end

    test "a ticket with no comments has no comments heading" do
      refute Markdown.render(@ticket, [], []) =~ "## Comments"
    end

    test "a ticket with no files has no files heading" do
      refute Markdown.render(@ticket, [], []) =~ "## Files"
    end

    test "a file that's still where you left it is listed as its path" do
      output = Markdown.render(@ticket, [], [on_disk("/home/dc/skillz/ci/validate.mjs")])

      assert output =~ "## Files"
      assert output =~ "- /home/dc/skillz/ci/validate.mjs\n"
    end

    test "a pinned file offers the copy alongside the original" do
      output =
        Markdown.render(@ticket, [], [
          on_disk("/home/dc/skillz/ci/validate.mjs", pinned: "/store/ab/cdef")
        ])

      assert output =~ "- /home/dc/skillz/ci/validate.mjs — pinned copy: /store/ab/cdef\n"
    end

    test "a file that's gone says so, and points at what survived it" do
      output = Markdown.render(@ticket, [], [missing("/tmp/run.log", pinned: "/store/ef/1234")])

      assert output =~ "- /tmp/run.log — MISSING; pinned copy: /store/ef/1234\n"
    end

    test "a file that's gone with nothing kept says that too, rather than a dead path" do
      output = Markdown.render(@ticket, [], [missing("/tmp/run.log")])

      assert output =~ "- /tmp/run.log — MISSING; no copy was kept\n"
    end

    test "a dropped file is listed by name, and resolves to the copy" do
      output = Markdown.render(@ticket, [], [upload("Screenshot.png", pinned: "/store/12/3456")])

      assert output =~ "- Screenshot.png — pinned copy: /store/12/3456\n"
    end

    test "every file line ends in a path something can read" do
      output =
        Markdown.render(@ticket, [], [
          on_disk("/home/dc/live.mjs"),
          on_disk("/home/dc/also-live.mjs", pinned: "/store/aa/1111"),
          missing("/tmp/gone.log", pinned: "/store/bb/2222"),
          upload("Screenshot.png", pinned: "/store/cc/3333")
        ])

      readable =
        output
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "- "))
        |> Enum.map(&(&1 |> String.split(" ") |> List.last()))

      assert readable == [
               "/home/dc/live.mjs",
               "/store/aa/1111",
               "/store/bb/2222",
               "/store/cc/3333"
             ]
    end
  end

  defp on_disk(path, opts \\ []), do: entry(:path, path, :on_disk, opts)
  defp missing(path, opts \\ []), do: entry(:path, path, :missing, opts)
  defp upload(name, opts), do: entry(:upload, name, :upload, opts)

  defp entry(origin, value, status, opts) do
    pinned = Keyword.get(opts, :pinned)

    %{
      sinker: %Sinker{
        type: :file,
        origin: origin,
        value: value,
        snapshot: pinned && %Snapshot{sha256: Path.basename(pinned)}
      },
      status: status,
      snapshot_path: pinned
    }
  end
end
