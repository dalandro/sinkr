defmodule Sinkr.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SinkrWeb.Telemetry,
        Sinkr.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:sinkr, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:sinkr, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Sinkr.PubSub},
        # Start to serve requests, typically the last entry
        SinkrWeb.Endpoint
      ] ++ herdr_poller() ++ reminder_scheduler()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sinkr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SinkrWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Off in test only: tests that want a poller start their own, with a lister
  # they control, instead of one loose polling the real CLI mid-suite.
  defp herdr_poller do
    if Application.get_env(:sinkr, :start_herdr_poller, true) do
      [{Sinkr.Herdr.Poller, name: Sinkr.Herdr.Poller}]
    else
      []
    end
  end

  # Off in test only, same as the poller: a scheduler test brings its own
  # clock and notifier rather than ringing real reminders mid-suite.
  defp reminder_scheduler do
    if Application.get_env(:sinkr, :start_reminder_scheduler, true) do
      [{Sinkr.Reminders.Scheduler, name: Sinkr.Reminders.Scheduler}]
    else
      []
    end
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
