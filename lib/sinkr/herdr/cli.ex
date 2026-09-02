defmodule Sinkr.Herdr.CLI do
  @moduledoc """
  The real herdr binary. Talks in raw output and exit codes; making sense of
  what it said is `Sinkr.Herdr`'s job. Tests swap this module out via the
  `:herdr_cli` app env, so nothing in a test run ever shells out.

  A machine without herdr on it answers `{:error, :enoent}` like any other
  failed call — the dashboard's herdr features go quiet rather than down.
  """

  @doc "Raw `herdr workspace list` output."
  def list_workspaces do
    case run(["workspace", "list"]) do
      {output, 0} -> {:ok, output}
      {output, _status} -> {:error, output}
    end
  end

  @doc "Renames a workspace; the label shows up in the next `list`."
  def rename_workspace(workspace_id, label) do
    case run(["workspace", "rename", workspace_id, label]) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, output}
    end
  end

  defp run(args) do
    System.cmd("herdr", args, stderr_to_stdout: true)
  rescue
    ErlangError -> {"", :enoent}
  end
end
