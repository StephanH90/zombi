defmodule ZombiWeb.ResourcesLive do
  use ZombiWeb, :live_view

  alias Zombi.SystemStats

  @capacity 120

  def mount(_params, _session, socket) do
    samples =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Zombi.PubSub, Zombi.StatsCollector.topic())
        Zombi.StatsCollector.history()
      else
        []
      end

    {:ok, assign(socket, :samples, samples)}
  end

  def handle_info({:stats_sample, sample}, socket) do
    samples = (socket.assigns.samples ++ [sample]) |> Enum.take(-@capacity)
    {:noreply, assign(socket, :samples, samples)}
  end

  def render(assigns) do
    latest = List.last(assigns.samples)
    assigns = assign(assigns, latest: latest, cores: (latest && latest.cpu) || [])

    ~H"""
    <Layouts.app flash={@flash}>
      <Layouts.tabs active={:resources} />
      <div class="flex flex-col gap-6 py-10">
        <h1 class="text-2xl font-semibold text-center">Server Resources</h1>

        <%= if @latest do %>
          <div class="card bg-base-200 p-4">
            <h2 class="font-semibold mb-3">CPU — per core</h2>
            <div class="grid gap-x-6 gap-y-3 sm:grid-cols-2">
              <div :for={core <- @cores}>
                <div class="flex items-center justify-between text-sm">
                  <span>Core {core.id}</span>
                  <span class="font-medium">{core.percent}%</span>
                </div>
                <.sparkline values={core_series(@samples, core.id)} class="text-primary" />
              </div>
            </div>
          </div>

          <div class="card bg-base-200 p-4">
            <h2 class="font-semibold mb-3">Memory</h2>
            <div class="flex items-center justify-between text-sm">
              <span :if={@latest.memory}>
                {SystemStats.format_bytes(@latest.memory.used)} / {SystemStats.format_bytes(
                  @latest.memory.total
                )}
              </span>
              <span :if={@latest.memory} class="font-medium">{@latest.memory.percent}%</span>
            </div>
            <.sparkline values={memory_series(@samples)} class="text-secondary" />
          </div>
        <% else %>
          <div class="text-center text-base-content/60">
            <span class="loading loading-spinner loading-sm"></span> Waiting for the first sample…
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp core_series(samples, id) do
    Enum.map(samples, fn s ->
      case Enum.find(s.cpu, &(&1.id == id)) do
        %{percent: p} -> p
        nil -> 0.0
      end
    end)
  end

  defp memory_series(samples) do
    Enum.map(samples, fn s -> (s.memory && s.memory.percent) || 0.0 end)
  end

  # Server-rendered SVG line graph. viewBox is a fixed 100x30 grid stretched to
  # the container width; values are percentages (0-100).
  attr :values, :list, required: true
  attr :class, :string, default: ""

  defp sparkline(assigns) do
    ~H"""
    <svg
      viewBox="0 0 100 30"
      preserveAspectRatio="none"
      class={["w-full h-12 mt-1", @class]}
      aria-hidden="true"
    >
      <polyline
        points={spark_points(@values)}
        fill="none"
        stroke="currentColor"
        stroke-width="1"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  defp spark_points(values) when length(values) < 2, do: ""

  defp spark_points(values) do
    n = length(values)
    step = 100 / (n - 1)

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {v, i} ->
      x = Float.round(i * step, 2)
      y = Float.round(30 - min(v, 100) / 100 * 30, 2)
      "#{x},#{y}"
    end)
  end
end
