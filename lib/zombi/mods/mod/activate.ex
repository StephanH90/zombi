defmodule Zombi.Mods.Mod.Activate do
  @moduledoc """
  Implementation of the `Zombi.Mods.Mod.activate` generic action.

  Dedupes the given workshop/mod id lists, persists them to the server config,
  restarts the game server, and returns the persisted payload.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, _context) do
    payload = %{
      workshop_ids: Enum.uniq(input.arguments.workshop_ids),
      mod_ids: Enum.uniq(input.arguments.mod_ids)
    }

    with :ok <- Zombi.ModConfig.write_mods(payload),
         {:ok, _output} <- Zombi.GameServer.restart() do
      {:ok, payload}
    end
  end
end
