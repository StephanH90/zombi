defmodule ZombiWeb.PlayersLive do
  use ZombiWeb, :live_view

  alias Zombi.Stats

  @refresh_ms 1_000

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  defp load(socket) do
    players = Stats.list_players!(query: [sort: [online: :desc, username: :asc]])
    histories = Map.new(players, fn p -> {p.username, kills_per_minute(p.username)} end)
    assign(socket, players: players, histories: histories, events: Stats.recent_events!())
  end

  # Kills per minute over the last 30 minutes: take the cumulative kill count
  # at the end of each minute, then the per-minute delta (clamped at 0 for
  # death / new character). One bar per minute.
  defp kills_per_minute(username) do
    since = DateTime.add(DateTime.utc_now(), -30, :minute)

    username
    |> Stats.player_history!(since)
    |> Enum.group_by(&minute_key(&1.inserted_at))
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map(fn {_key, snaps} -> List.last(snaps).zombie_kills || 0 end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> max(b - a, 0) end)
  end

  defp minute_key(%DateTime{} = dt), do: {dt.year, dt.month, dt.day, dt.hour, dt.minute}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <Layouts.tabs active={:players} />
      <div class="flex flex-col gap-6 py-10">
        <h1 class="text-2xl font-semibold">Players</h1>

        <%= if @players == [] do %>
          <div class="alert alert-info">
            No player data yet. This fills in once the ZombiStats mod is active and players have joined.
          </div>
        <% else %>
          <div class="flex flex-col gap-5">
            <div :for={p <- @players} class="card bg-base-200 p-5">
              <div class="flex flex-wrap items-baseline justify-between gap-2 mb-3">
                <div class="flex items-center gap-2">
                  <span class="font-semibold text-xl">{p.username}</span>
                  <span :if={p.online} class="badge badge-success">Online</span>
                  <span :if={!p.online} class="badge badge-ghost">Offline</span>
                </div>
                <div class="flex items-center gap-5 text-sm text-base-content/60">
                  <span><span class="font-semibold text-base-content text-base">{p.zombie_kills}</span> kills</span>
                  <span><span class="font-semibold text-base-content text-base">{fmt_hours(p.hours_survived)}</span> h survived</span>
                  <span><span class="font-semibold text-base-content text-base">{fmt_pct(p.health)}</span> health</span>
                  <span class="text-sm text-base-content/40">seen {fmt_time(p.last_seen_at)}</span>
                </div>
              </div>

              <div class="flex items-end justify-between mb-1">
                <span class="text-sm font-medium text-base-content/70">Kills per minute · last 30 min</span>
                <span class="text-2xl font-bold text-primary tabular-nums">
                  {fmt_rate(latest(@histories[p.username]))}
                </span>
              </div>
              <.bars values={@histories[p.username]} class="text-primary" />
              <div class="flex justify-between text-xs text-base-content/40 mt-1">
                <span>{length(@histories[p.username] || [])} min</span>
                <span :if={peak(@histories[p.username])}>peak {peak(@histories[p.username])}/min</span>
              </div>
            </div>
          </div>
        <% end %>

        <h2 class="text-xl font-semibold mt-4">Activity</h2>
        <%= if @events == [] do %>
          <p class="text-base-content/60">No events yet.</p>
        <% else %>
          <ul class="divide-y divide-base-300 rounded-box border border-base-300">
            <li :for={e <- @events} class="flex items-center gap-3 p-2 text-sm">
              <span class={["badge badge-sm", event_badge(e.kind)]}>{e.kind}</span>
              <span class="font-medium">{e.username}</span>
              <span class="text-base-content/50 ml-auto">{fmt_time(e.inserted_at)}</span>
            </li>
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp event_badge(:join), do: "badge-success"
  defp event_badge(:leave), do: "badge-warning"
  defp event_badge(:death), do: "badge-error"
  defp event_badge(_), do: "badge-ghost"

  defp fmt_hours(nil), do: "—"
  defp fmt_hours(h), do: "#{Float.round(h * 1.0, 1)}"

  defp fmt_pct(nil), do: "—"
  defp fmt_pct(v), do: "#{round(v)}%"

  defp fmt_time(nil), do: "—"
  defp fmt_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp latest(values) when is_list(values) and values != [], do: List.last(values)
  defp latest(_), do: nil

  defp peak([_ | _] = values), do: Enum.max(values)
  defp peak(_), do: nil

  defp fmt_rate(nil), do: "—"
  defp fmt_rate(v), do: "#{v}/min"

  attr :values, :list, required: true
  attr :class, :string, default: ""

  defp bars(assigns) do
    ~H"""
    <svg
      viewBox="0 0 100 40"
      preserveAspectRatio="none"
      class={["w-full h-64 bg-base-300 rounded-box", @class]}
      aria-hidden="true"
    >
      <rect
        :for={r <- bar_rects(@values)}
        x={r.x}
        y={r.y}
        width={r.w}
        height={r.h}
        fill="currentColor"
      />
    </svg>
    """
  end

  defp bar_rects(values) when not is_list(values) or values == [], do: []

  defp bar_rects(values) do
    n = length(values)
    step = 100 / n
    max = max(Enum.max(values), 1)

    values
    |> Enum.with_index()
    |> Enum.map(fn {v, i} ->
      height = Float.round(v / max * 40, 2)
      %{x: Float.round(i * step, 2), y: Float.round(40 - height, 2), w: Float.round(step * 0.85, 2), h: height}
    end)
  end
end
