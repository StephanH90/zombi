defmodule Zombi.StatsIngester do
  @moduledoc """
  Periodically reads the server-side mod's output files and persists them via
  the `Zombi.Stats` domain. All the business logic (upsert, snapshot, join/leave
  diffing) lives in the `Player.ingest` action; this process only does the file
  IO and scheduling.
  """
  use GenServer
  require Logger

  @interval_ms 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    # Skip death lines already in the file so we don't replay history on boot.
    schedule()
    {:ok, %{deaths_offset: length(death_lines())}}
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
        try do
          Zombi.Stats.ingest_sample!(details)
        rescue
          e -> Logger.warning("stats ingest failed: #{Exception.message(e)}")
        end

      _ ->
        :ok
    end

    state
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
