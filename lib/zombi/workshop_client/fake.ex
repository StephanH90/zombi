defmodule Zombi.WorkshopClient.Fake do
  @moduledoc """
  Canned `Zombi.WorkshopClient` implementation for dev/test so the confirm flow
  can be exercised without hitting Steam.
  """

  @behaviour Zombi.WorkshopClient

  @impl true
  def fetch_mod_info(workshop_id) when is_binary(workshop_id) do
    {:ok, %{title: "Fake Mod #{workshop_id}", mod_ids: ["FakeModA", "FakeModB"]}}
  end
end
