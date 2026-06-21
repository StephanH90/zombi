defmodule Zombi.GameServer do
  @moduledoc """
  Controls the Project Zomboid game server.

  This module is both the behaviour definition and the dispatcher to the
  configured implementation (`Zombi.GameServer.Docker` by default).
  """

  @callback restart() :: {:ok, String.t()} | {:error, String.t()}
  @callback version() :: {:ok, %{version: String.t(), date: String.t()}} | {:error, String.t()}

  def impl, do: Application.get_env(:zombi, :game_server, Zombi.GameServer.Docker)

  def restart, do: impl().restart()

  def version, do: impl().version()

  defdelegate parse_version(output), to: Zombi.GameServer.Docker
end
