defmodule Zombi.Mods.Mod.ResolveLink do
  @moduledoc "Implementation of the `Zombi.Mods.Mod.resolve_link` generic action."
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, _context) do
    with {:ok, id} <- Zombi.Workshop.url_to_id(input.arguments.link),
         {:ok, info} <- Zombi.WorkshopClient.impl().fetch_mod_info(id) do
      {:ok, %{workshop_id: id, title: info.title, mod_ids: info.mod_ids}}
    end
  end
end
