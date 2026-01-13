defmodule DocCoffeeLite.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DocCoffeeLiteWeb.Telemetry,
      DocCoffeeLite.Repo,
      {DNSCluster, query: Application.get_env(:doc_coffee_lite, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DocCoffeeLite.PubSub},
      {Oban, Application.fetch_env!(:doc_coffee_lite, Oban)},
      # Start a worker by calling: DocCoffeeLite.Worker.start_link(arg)
      # {DocCoffeeLite.Worker, arg},
      # Start to serve requests, typically the last entry
      DocCoffeeLiteWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DocCoffeeLite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DocCoffeeLiteWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
