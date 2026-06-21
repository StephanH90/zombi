defmodule Zombi.Mods.Mod.List do
  @moduledoc """
  Implementation of the `Zombi.Mods.Mod.list` generic action.

  Returns one `Zombi.Mods.Mod` struct per configured workshop id. The flat
  `mod_ids` from the config are not mapped to individual workshop items by the
  ini, so each struct carries `mod_ids: []`; use `Zombi.Mods.current_mods/0`
  for the full mod-id list.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(_input, _opts, _context) do
    with {:ok, %{workshop_ids: workshop_ids}} <- Zombi.ModConfig.read_mods() do
      mods =
        Enum.map(workshop_ids, fn id ->
          %Zombi.Mods.Mod{workshop_id: id, title: id, mod_ids: []}
        end)

      {:ok, mods}
    end
  end
end
