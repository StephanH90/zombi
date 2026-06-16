defmodule Zombi.GameStats do
  @moduledoc """
  Reads the in-game stats file written by the server-side `ZombiStats` Lua mod
  (player count and loaded-zombie count). Returns `{:error, :unavailable}` until
  the mod is active and has written the file.
  """

  @doc "Returns `{:ok, %{players, zombies, ts}}` or `{:error, :unavailable}`."
  def read do
    with {:ok, body} <- File.read(path()),
         {:ok, %{"players" => players, "zombies" => zombies} = json} <- Jason.decode(body) do
      {:ok, %{players: players, zombies: zombies, ts: json["ts"]}}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp path do
    # getFileWriter in the mod writes into the Zomboid data dir's Lua/ folder.
    Path.join(Application.fetch_env!(:zombi, :compose_dir), "server-data/Lua/zombi-stats.json")
  end
end
