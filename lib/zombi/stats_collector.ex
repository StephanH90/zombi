defmodule Zombi.StatsCollector do
  @moduledoc """
  Samples host CPU/memory twice a second and broadcasts each sample over
  PubSub, keeping a short rolling history for graphs. Sampling centrally (one
  process) keeps `:cpu_sup.util/1` accurate — concurrent callers would reset
  each other's counters.
  """
  use GenServer

  @topic "system_stats"
  @interval_ms 500
  @capacity 120

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "PubSub topic that receives `{:stats_sample, sample}` messages."
  def topic, do: @topic

  @doc "Current rolling history, oldest sample first."
  def history, do: GenServer.call(__MODULE__, :history)

  @impl true
  def init(_) do
    # Prime cpu_sup so the first real sample measures a fresh interval.
    Zombi.SystemStats.sample()
    schedule()
    {:ok, %{history: []}}
  end

  @impl true
  def handle_call(:history, _from, state) do
    {:reply, Enum.reverse(state.history), state}
  end

  @impl true
  def handle_info(:tick, state) do
    sample = Zombi.SystemStats.sample()
    Phoenix.PubSub.broadcast(Zombi.PubSub, @topic, {:stats_sample, sample})
    schedule()
    {:noreply, %{state | history: Enum.take([sample | state.history], @capacity)}}
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval_ms)
end
