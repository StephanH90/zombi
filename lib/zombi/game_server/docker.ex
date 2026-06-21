defmodule Zombi.GameServer.Docker do
  @moduledoc """
  Controls the Project Zomboid docker compose deployment.
  """

  @behaviour Zombi.GameServer

  @doc """
  Restarts the server by running `docker compose restart` in the configured
  compose directory.

  Returns `{:ok, output}` on success or `{:error, message}` on failure.
  """
  @impl true
  def restart do
    dir = Application.fetch_env!(:zombi, :compose_dir)

    case System.cmd("docker", ["compose", "restart"], cd: dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "docker exited with #{code}: #{output}"}
    end
  end

  @doc """
  Reads the running Project Zomboid build version from the container logs.

  Returns `{:ok, %{version, date}}` or `{:error, reason}`.
  """
  @impl true
  def version do
    container = Application.fetch_env!(:zombi, :pz_container)

    # The version is logged at startup (oldest lines), so read from the start
    # and stop at the first match — grep -m1 keeps this cheap on large logs.
    cmd = "docker logs #{container} 2>&1 | grep -m1 'version='"

    case System.cmd("sh", ["-c", cmd]) do
      {output, 0} -> parse_version(output)
      {_output, _} -> {:error, "version not found in logs"}
    end
  end

  @doc false
  def parse_version(output) do
    # Log line: "version=42.19.0 <hash> 2026-06-01 09:40:02 (ZB) demo=false"
    case Regex.scan(~r/version=(\S+)\s+\S+\s+(\d{4}-\d{2}-\d{2})/, output) do
      [] -> {:error, "version not found in recent logs"}
      matches -> match_to_version(List.last(matches))
    end
  end

  defp match_to_version([_, version, date]), do: {:ok, %{version: version, date: date}}
end
