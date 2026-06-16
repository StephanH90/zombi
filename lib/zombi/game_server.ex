defmodule Zombi.GameServer do
  @moduledoc """
  Controls the Project Zomboid docker compose deployment.
  """

  @doc """
  Restarts the server by running `docker compose restart` in the configured
  compose directory.

  Returns `{:ok, output}` on success or `{:error, message}` on failure.
  """
  def restart do
    dir = Application.fetch_env!(:zombi, :compose_dir)

    case System.cmd("docker", ["compose", "restart"], cd: dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "docker exited with #{code}: #{output}"}
    end
  end
end
