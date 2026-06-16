defmodule Zombi.StatsIngester do
  @moduledoc """
  Periodically reads the server-side mod's output files and persists them via
  the `Zombi.Stats` domain. All the business logic (upsert, snapshot, join/leave
  diffing) lives in the `Player.ingest` action; this process only does the file
  IO and scheduling.
  """
  use GenServer
  require Logger

  # Upsert current stats + join/leave events frequently; take history snapshots
  # (for graphs) much less often so the DB doesn't bloat.
  @interval_ms 5_000
  @snapshot_every_ms 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    # Skip death lines already in the file so we don't replay history on boot.
    schedule()
    {:ok, %{deaths_offset: length(death_lines()), last_snapshot: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      state
      |> ingest_players()
      |> ingest_deaths()

    schedule()
    {:noreply, state}
  end

  defp ingest_players(state) do
    case Zombi.GameStats.read() do
      {:ok, %{player_details: details}} ->
        safely(fn -> Zombi.Stats.ingest_sample!(details) end, "stats ingest")
        maybe_snapshot(state, details)

      _ ->
        state
    end
  end

  defp maybe_snapshot(state, details) do
    now = System.monotonic_time(:millisecond)

    if state.last_snapshot == nil or now - state.last_snapshot >= @snapshot_every_ms do
      safely(
        fn ->
          Enum.each(details, fn p ->
            Zombi.Stats.create_snapshot!(%{
              username: p.name,
              zombie_kills: p.kills,
              hours_survived: p.hours
            })
          end)
        end,
        "snapshot"
      )

      %{state | last_snapshot: now}
    else
      state
    end
  end

  defp safely(fun, label) do
    fun.()
  rescue
    e -> Logger.warning("#{label} failed: #{Exception.message(e)}")
  end

  defp ingest_deaths(state) do
    lines = death_lines()
    new = Enum.drop(lines, state.deaths_offset)

    Enum.each(new, fn line ->
      with {:ok, %{"name" => name}} <- Jason.decode(line) do
        try do
          Zombi.Stats.log_event!(%{kind: :death, username: name})
        rescue
          e -> Logger.warning("death log failed: #{Exception.message(e)}")
        end
      end
    end)

    %{state | deaths_offset: length(lines)}
  end

  defp death_lines do
    case File.read(events_path()) do
      {:ok, body} -> body |> String.split("\n", trim: true)
      _ -> []
    end
  end

  defp events_path do
    Path.join(Application.fetch_env!(:zombi, :compose_dir), "server-data/Lua/zombi-events.json")
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval_ms)
end
