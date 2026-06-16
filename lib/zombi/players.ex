defmodule Zombi.Players do
  @moduledoc """
  Reports who is currently connected to the Project Zomboid server via RCON,
  so an admin can tell whether restarting will kick anyone off.
  """

  @doc """
  Returns `{:ok, %{count, names}}` for the players currently online, or
  `{:error, reason}` (e.g. the server is unreachable because it's down).
  """
  def online do
    case Zombi.Rcon.command("players") do
      {:ok, body} -> {:ok, parse(body)}
      {:error, reason} -> {:error, friendly_error(reason)}
    end
  end

  @doc false
  def parse(body) do
    count =
      case Regex.run(~r/Players connected \((\d+)\)/, body) do
        [_, n] -> String.to_integer(n)
        nil -> 0
      end

    names =
      ~r/^-(.+)$/m
      |> Regex.scan(body, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{count: count, names: names}
  end

  defp friendly_error(:auth_failed), do: "RCON password rejected"
  defp friendly_error(:econnrefused), do: "server not reachable (it may be offline)"
  defp friendly_error(:timeout), do: "RCON timed out"
  defp friendly_error(reason), do: "RCON error: #{inspect(reason)}"
end
