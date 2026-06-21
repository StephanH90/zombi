defmodule Zombi.GameServer.Fake do
  @moduledoc """
  Fake game server implementation for dev and test.

  Returns canned responses instead of shelling out to docker.
  """

  @behaviour Zombi.GameServer

  require Logger

  @impl true
  def restart do
    Logger.info("[GameServer.Fake] restart")
    {:ok, "fake: docker compose restart\n"}
  end

  @impl true
  def version do
    {:ok, %{version: "42.19.0", date: "2026-06-01"}}
  end
end
