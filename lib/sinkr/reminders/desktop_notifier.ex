defmodule Sinkr.Reminders.DesktopNotifier do
  @moduledoc """
  Puts a reminder on the desktop through `notify-send`, the freedesktop
  notification CLI. Needs the server to have been started from a session
  that can reach the D-Bus session bus — a terminal in the desktop session
  does. A missing binary or a refused bus is logged and shrugged off; the
  strip in the app still rings.
  """

  require Logger

  @app_name "sinkr"

  def notify(title) do
    case System.find_executable("notify-send") do
      nil ->
        Logger.warning("reminder not shown on desktop: notify-send not found")

      notify_send ->
        case System.cmd(notify_send, ["--app-name", @app_name, "Reminder", title],
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            :ok

          {output, status} ->
            Logger.warning("notify-send exited #{status}: #{String.trim(output)}")
        end
    end

    :ok
  end
end
