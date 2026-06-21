defmodule Zombi.Mods do
  @moduledoc """
  Ash domain modelling the active Project Zomboid mod list.

  This domain uses the Simple data layer (no persistence): every action is a
  generic action that delegates IO to the already-built behaviours
  (`Zombi.ModConfig`, `Zombi.WorkshopClient`, `Zombi.Workshop`,
  `Zombi.GameServer`).

  ## Code interface (what the LiveView depends on)

    * `current_mods/0` (`current_mods!/0`) → `%{workshop_ids: [String.t()], mod_ids: [String.t()]}`
      The flat, source-of-truth lists read from the active server config. This is
      the primary data source for staging in the UI.

    * `list_mods/0` (`list_mods!/0`) → `[%Zombi.Mods.Mod{}]`
      One `Mod` struct per configured workshop id, for display. The flat
      `mod_ids` are *not* split per workshop item (the ini does not record that
      mapping), so each struct carries `mod_ids: []`. Use `current_mods/0` for
      the actual mod-id list.

    * `resolve_link/1` (`resolve_link!/1`) → `%{workshop_id, title, mod_ids}`
      Given a workshop URL or bare id, fetches the mod info from the workshop
      client so the UI can pre-fill the add-mod form.

    * `activate_mods/2` (`activate_mods!/2`) → `%{workshop_ids, mod_ids}`
      Dedupes the given lists, writes them to the server config, restarts the
      game server, and returns the persisted payload.
  """
  use Ash.Domain, otp_app: :zombi, extensions: [AshPhoenix]

  forms do
    form :resolve_link, args: [:link]
  end

  resources do
    resource Zombi.Mods.Mod do
      define :current_mods, action: :current
      define :list_mods, action: :list
      define :resolve_link, action: :resolve_link, args: [:link]
      define :activate_mods, action: :activate, args: [:workshop_ids, :mod_ids]
    end
  end
end
