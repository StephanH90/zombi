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

  # Kills-per-minute over time, derived from consecutive cumulative-kill
  # snapshots (delta kills / delta minutes). Negative deltas (death / new
  # character) clamp to 0.
  defp kills_per_minute(username) do
    username
    |> Stats.player_history!()
    |> Enum.reverse()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      minutes = DateTime.diff(b.inserted_at, a.inserted_at, :second) / 60
      delta = (b.zombie_kills || 0) - (a.zombie_kills || 0)
      if minutes > 0, do: Float.round(max(delta, 0) / minutes, 1), else: 0.0
    end)
  end

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
          <div class="overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th>Player</th>
                  <th>Status</th>
                  <th class="text-right">Kills</th>
                  <th class="text-right">Hours</th>
                  <th class="text-right">Health</th>
                  <th>Last seen</th>
                  <th class="w-96">Kills/min</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={p <- @players}>
                  <td class="font-medium">{p.username}</td>
                  <td>
                    <span :if={p.online} class="badge badge-success badge-sm">Online</span>
                    <span :if={!p.online} class="badge badge-ghost badge-sm">Offline</span>
                  </td>
                  <td class="text-right">{p.zombie_kills}</td>
                  <td class="text-right">{fmt_hours(p.hours_survived)}</td>
                  <td class="text-right">{fmt_pct(p.health)}</td>
                  <td class="text-sm text-base-content/60">{fmt_time(p.last_seen_at)}</td>
                  <td>
                    <div class="flex items-center gap-2">
                      <.bars values={@histories[p.username]} class="text-primary" />
                      <span class="text-xs tabular-nums whitespace-nowrap text-base-content/70">
                        {fmt_rate(latest(@histories[p.username]))}
                      </span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
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

  defp fmt_rate(nil), do: "—"
  defp fmt_rate(v), do: "#{v}/min"

  attr :values, :list, required: true
  attr :class, :string, default: ""

  defp bars(assigns) do
    ~H"""
    <svg viewBox="0 0 100 36" preserveAspectRatio="none" class={["w-72 h-24", @class]} aria-hidden="true">
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
      height = Float.round(v / max * 36, 2)
      %{x: Float.round(i * step, 2), y: Float.round(36 - height, 2), w: Float.round(step * 0.8, 2), h: height}
    end)
  end
end
