defmodule Sinkr.CLI do
  @moduledoc """
  The terminal-only surface for a ticket: what you get when you say "see
  s-16, let's carry on" with no browser open and no server necessarily
  running.

  `run/1` holds all the behaviour and is what the tests exercise, since it
  assumes `Sinkr.Repo` is already started and just returns `{:ok, string}` or
  `{:error, string}` rather than touching stdout or the VM. `main/1` is the
  thin wrapper the `bin/sinkr` script calls: it starts the one thing this
  needs, prints, and halts.
  """

  alias Sinkr.Tickets
  alias Sinkr.Tickets.Markdown
  alias Sinkr.Tickets.Ticket

  @usage """
  Usage: sinkr <command> [args]

  Commands:
    show <ref>   Show a ticket by ref, e.g. sinkr show s-12
    list         List every ticket
  """

  @doc """
  Runs a command against already-started app state and returns its output
  rather than printing it, so this is testable without capturing IO or
  booting a VM per test.
  """
  def run(["show", ref]) do
    ticket = Tickets.get_ticket_by_ref!(ref)
    entries = Tickets.file_entries(ticket)
    {:ok, Markdown.render(ticket, entries)}
  rescue
    Ecto.NoResultsError -> {:error, "No ticket for #{ref}"}
  end

  def run(["list"]) do
    case Tickets.list_tickets() do
      [] -> {:ok, "Nothing to show.\n"}
      tickets -> {:ok, Enum.map_join(tickets, &list_line/1)}
    end
  end

  def run(_argv), do: {:error, @usage}

  defp list_line(ticket) do
    "#{Ticket.display_ref(ticket)}  #{ticket.title}  (#{ticket.status})\n"
  end

  @doc """
  The entry point `bin/sinkr` calls.

  Starts `Sinkr.Repo` only — never `SinkrWeb.Endpoint` — so this never fights
  a running dev server for port 4040; SQLite's WAL mode makes concurrent
  reads with a live server safe. `Application.ensure_all_started(:sinkr)`
  would start the endpoint too, since `Sinkr.Application` supervises it
  alongside the repo, so instead this brings up just the dependency apps the
  repo itself needs (the ecto/sqlite driver stack) and starts the repo
  directly.

  Not exercised by the test suite: it halts the VM, which a test process
  can't survive, so it stays thin enough that `run/1` carries all the
  behaviour worth testing.
  """
  def main(argv) do
    # Dev logs Ecto's query debug lines to stdout by default, which would
    # otherwise land in the middle of the output an agent is trying to read.
    Logger.configure(level: :warning)

    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Sinkr.Repo.start_link()

    case run(argv) do
      {:ok, output} ->
        IO.write(output)
        System.halt(0)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end
end
