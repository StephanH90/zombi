defmodule Zombi.Stats.Player.Ingest do
  @moduledoc """
  Implementation of the `Zombi.Stats.Player.ingest` generic action.

  Given the players currently online (from the server-side mod), upserts each
  player's latest stats, records a snapshot for graphing, and logs join/leave
  events by diffing against the players currently flagged online in the DB.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, _context) do
    players = input.arguments.players
    online_names = MapSet.new(players, &name/1)

    previously_online = Zombi.Stats.list_players!(query: [filter: [online: true]])
    prev_names = MapSet.new(previously_online, & &1.username)

    Enum.each(players, fn p ->
      n = name(p)

      Zombi.Stats.record_player!(n, %{
        hours_survived: num(p, :hours),
        zombie_kills: int(p, :kills),
        health: num(p, :health)
      })

      Zombi.Stats.create_snapshot!(%{
        username: n,
        zombie_kills: int(p, :kills),
        hours_survived: num(p, :hours)
      })

      unless MapSet.member?(prev_names, n) do
        Zombi.Stats.log_event!(%{kind: :join, username: n})
      end
    end)

    previously_online
    |> Enum.reject(&MapSet.member?(online_names, &1.username))
    |> Enum.each(fn player ->
      Zombi.Stats.mark_player_offline!(player)
      Zombi.Stats.log_event!(%{kind: :leave, username: player.username})
    end)

    {:ok, %{online: MapSet.size(online_names)}}
  end

  defp name(p), do: Map.get(p, :name) || Map.get(p, "name")
  defp num(p, key), do: (Map.get(p, key) || Map.get(p, to_string(key)) || 0) * 1.0
  defp int(p, key), do: trunc(Map.get(p, key) || Map.get(p, to_string(key)) || 0)
end
