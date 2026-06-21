defmodule Zombi.WorkshopClient do
  @moduledoc """
  Fetches a Steam Workshop page and scrapes the internal Project Zomboid mod
  IDs that authors conventionally publish in the description.

  PZ servers load mods by their internal mod-id strings (the `Mods=` line),
  which are not derivable from the numeric workshop id. Authors typically write
  them as `Mod ID: SomeId` (sometimes several per workshop item). We scrape
  these so the UI can pre-fill them for the user to confirm.

  The active implementation is configurable so dev/test can use a fake:

      config :zombi, workshop_client: Zombi.WorkshopClient.Steam
  """

  @callback fetch_mod_info(workshop_id :: String.t()) ::
              {:ok, %{title: String.t(), mod_ids: [String.t()]}} | {:error, term}

  @doc "The configured implementation module (defaults to the real Steam client)."
  def impl, do: Application.get_env(:zombi, :workshop_client, Zombi.WorkshopClient.Steam)
end
