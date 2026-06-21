defmodule Zombi.Mods.Mod.Current do
  @moduledoc "Implementation of the `Zombi.Mods.Mod.current` generic action."
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(_input, _opts, _context) do
    Zombi.ModConfig.read_mods()
  end
end
