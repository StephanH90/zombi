defmodule Zombi.Mods.Mod do
  @moduledoc """
  Models a single Project Zomboid workshop mod entry.

  Uses the Simple data layer (default, no persistence): all actions are generic
  and delegate IO to the `Zombi.ModConfig` / `Zombi.WorkshopClient` /
  `Zombi.GameServer` behaviours. See `Zombi.Mods` for the public code interface.
  """
  use Ash.Resource, otp_app: :zombi, domain: Zombi.Mods

  resource do
    # Only generic actions + struct attributes; no persistence, so no primary key.
    require_primary_key? false
  end

  actions do
    action :current, :map do
      description "Returns the current active mod lists as a flat %{workshop_ids:, mod_ids:} map."
      run Zombi.Mods.Mod.Current
    end

    action :list, {:array, :struct} do
      description "Returns one Mod struct per configured workshop id."
      constraints items: [instance_of: __MODULE__]
      run Zombi.Mods.Mod.List
    end

    action :resolve_link, :map do
      description "Resolves a workshop URL or bare id to %{workshop_id, title, mod_ids}."
      argument :link, :string, allow_nil?: false
      run Zombi.Mods.Mod.ResolveLink
    end

    action :activate, :map do
      description "Dedupes, persists, and restarts to activate the given mod lists."
      argument :workshop_ids, {:array, :string}, allow_nil?: false
      argument :mod_ids, {:array, :string}, allow_nil?: false
      run Zombi.Mods.Mod.Activate
    end
  end

  attributes do
    attribute :workshop_id, :string, public?: true
    attribute :title, :string, public?: true
    attribute :mod_ids, {:array, :string}, public?: true
  end
end
