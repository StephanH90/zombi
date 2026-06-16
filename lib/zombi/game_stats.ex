defmodule Zombi.GameStats do
  @moduledoc """
  Reads the in-game stats file written by the server-side `ZombiStats` Lua mod.

  Newer versions of the mod write a per-player array; older ones wrote just a
  count. Both are handled. Returns `{:error, :unavailable}` until the mod is
  active and has written the file.
  """

  @doc """
  Returns `{:ok, %{players, zombies, ts, player_details}}` or
  `{:error, :unavailable}`. `players` is the online count; `player_details` is a
  list of `%{name, kills, hours, health}` (empty for the old mod format).
  """
  def read do
    with {:ok, body} <- File.read(path()),
         {:ok, json} <- Jason.decode(body) do
      {details, count} = players(json["players"])

      {:ok,
       %{
         players: count,
         zombies: json["zombies"] || 0,
         ts: json["ts"],
         player_details: details
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp players(list) when is_list(list) do
    details =
      Enum.map(list, fn p ->
        %{
          name: p["name"],
          kills: p["kills"] || 0,
          hours: p["hours"] || 0.0,
          health: p["health"] || 0.0
        }
      end)

    {details, length(details)}
  end

  defp players(count) when is_integer(count), do: {[], count}
  defp players(_), do: {[], 0}

  defp path do
    Path.join(Application.fetch_env!(:zombi, :compose_dir), "server-data/Lua/zombi-stats.json")
  end
end
