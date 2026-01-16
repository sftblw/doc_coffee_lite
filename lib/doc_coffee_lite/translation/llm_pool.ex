defmodule DocCoffeeLite.Translation.LlmPool do
  @moduledoc """
  Manages multiple LLM server endpoints with simple load balancing and health tracking.
  """
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Gets an available URL from the list of candidates.
  Prefers idle servers over busy ones.
  """
  def checkout(urls) when is_list(urls) do
    GenServer.call(__MODULE__, {:checkout, urls})
  end

  def checkout(url) when is_binary(url) do
    if String.contains?(url, ",") do
      urls = url |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      checkout(urls)
    else
      url
    end
  end

  @doc """
  Reports the completion of a request on a URL.
  """
  def checkin(url) do
    GenServer.cast(__MODULE__, {:checkin, url})
  end

  @doc """
  Reports a failure on a URL to temporarily deprioritize it.
  """
  def report_failure(url) do
    GenServer.cast(__MODULE__, {:report_failure, url})
  end

  # --- Server Callbacks ---

  @impl true
  def init(_) do
    # state: %{url => %{status: :idle | :busy, last_fail: nil, usage_count: 0, last_checkout: datetime | nil}}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:checkout, urls}, _from, state) do
    # Initialize unknown URLs
    state =
      Enum.reduce(urls, state, fn url, acc ->
        Map.put_new(acc, url, %{status: :idle, last_fail: nil, usage_count: 0, last_checkout: nil})
      end)

    # 1. Filter healthy URLs AND auto-release stale ones (10 mins)
    now = DateTime.utc_now()

    healthy_urls =
      Enum.filter(urls, fn url ->
        is_stale =
          case state[url].last_checkout do
            nil -> false
            # 10 minutes
            time -> DateTime.diff(now, time) > 600
          end

        is_healthy =
          case state[url].last_fail do
            nil -> true
            time -> DateTime.diff(now, time) > 60
          end

        is_healthy or is_stale
      end)

    candidates = if healthy_urls == [], do: urls, else: healthy_urls

    # 2. Select the one with LEAST usage among idle (or stale) ones
    selected =
      candidates
      |> Enum.sort_by(fn url ->
        is_busy =
          state[url].status == :busy and DateTime.diff(now, state[url].last_checkout || now) < 600

        {is_busy, state[url].usage_count}
      end)
      |> List.first()

    # 3. Mark as busy and increment usage
    new_state =
      state
      |> put_in([selected, :status], :busy)
      |> put_in([selected, :last_checkout], now)
      |> update_in([selected, :usage_count], &(&1 + 1))

    {:reply, selected, new_state}
  end

  @impl true
  def handle_cast({:checkin, url}, state) do
    new_state =
      if Map.has_key?(state, url) do
        put_in(state, [url, :status], :idle)
      else
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:report_failure, url}, state) do
    Logger.warning("LLM Server marked as unhealthy: #{url}")

    new_state =
      state
      |> put_in([url, :status], :idle)
      |> put_in([url, :last_fail], DateTime.utc_now())

    {:noreply, new_state}
  end
end
