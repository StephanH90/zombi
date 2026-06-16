defmodule Zombi.Workshop do
  @moduledoc """
  Detects Project Zomboid workshop mods that have a newer version on Steam
  than the one currently installed on the server.

  The server only pulls new workshop versions when it restarts (SteamCMD runs
  on boot). Clients auto-update mods, so a mod that updated on Steam but not on
  the server causes a version mismatch that blocks players from joining. This
  module surfaces those pending updates so an admin knows when a restart helps.
  """

  @steam_url "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"

  @doc """
  Returns `{:ok, updates}` where `updates` is a list of mods whose Steam version
  is newer than the installed version, or `{:error, reason}`.

  Each update is a map: `%{id, title, updated_at (DateTime), behind_seconds}`.
  An empty list means everything is up to date.
  """
  def pending_updates do
    with {:ok, ids} <- subscribed_ids(),
         {:ok, local} <- local_versions(),
         {:ok, remote} <- remote_details(ids) do
      updates =
        for id <- ids,
            details = remote[id],
            details != nil,
            installed = Map.get(local, id, 0),
            details.time_updated > installed do
          %{
            id: id,
            title: details.title,
            updated_at: DateTime.from_unix!(details.time_updated),
            behind_seconds: details.time_updated - installed
          }
        end

      {:ok, Enum.sort_by(updates, & &1.updated_at, {:desc, DateTime})}
    end
  end

  @doc "Workshop IDs the active server config loads (the `WorkshopItems=` line)."
  def subscribed_ids do
    case File.read(server_ini_path()) do
      {:ok, content} -> {:ok, parse_workshop_items(content)}
      {:error, reason} -> {:error, "could not read server ini: #{:file.format_error(reason)}"}
    end
  end

  @doc "Installed workshop versions from the SteamCMD manifest: `%{id => timeupdated}`."
  def local_versions do
    case File.read(acf_path()) do
      {:ok, content} -> {:ok, parse_acf(content)}
      {:error, reason} -> {:error, "could not read workshop manifest: #{:file.format_error(reason)}"}
    end
  end

  @doc "Current Steam details for the given IDs: `%{id => %{title, time_updated}}`."
  def remote_details([]), do: {:ok, %{}}

  def remote_details(ids) do
    form =
      [{"itemcount", length(ids)}] ++
        Enum.with_index(ids, fn id, i -> {"publishedfileids[#{i}]", id} end)

    case Req.post(@steam_url, form: form, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"response" => %{"publishedfiledetails" => details}}}} ->
        {:ok, index_remote(details)}

      {:ok, %{status: status}} ->
        {:error, "Steam API returned status #{status}"}

      {:error, reason} ->
        {:error, "Steam API request failed: #{inspect(reason)}"}
    end
  end

  # --- pure parsing helpers (unit tested) ---

  @doc false
  def parse_workshop_items(ini_content) do
    case Regex.run(~r/^WorkshopItems=(.*)$/m, ini_content, capture: :all_but_first) do
      [list] ->
        list
        |> String.split(";", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      nil ->
        []
    end
  end

  @doc false
  def parse_acf(acf_content) do
    ~r/"(\d+)"\s*\{[^{}]*?"timeupdated"\s*"(\d+)"/
    |> Regex.scan(acf_content, capture: :all_but_first)
    |> Enum.reduce(%{}, fn [id, ts], acc ->
      Map.update(acc, id, String.to_integer(ts), &max(&1, String.to_integer(ts)))
    end)
  end

  defp index_remote(details) do
    for %{"publishedfileid" => id} = d <- details,
        d["result"] == 1,
        into: %{} do
      {id, %{title: d["title"] || id, time_updated: d["time_updated"] || 0}}
    end
  end

  defp compose_dir, do: Application.fetch_env!(:zombi, :compose_dir)
  defp server_name, do: Application.fetch_env!(:zombi, :pz_server_name)

  defp acf_path,
    do: Path.join(compose_dir(), "server-files/steamapps/workshop/appworkshop_108600.acf")

  defp server_ini_path,
    do: Path.join(compose_dir(), "server-data/Server/#{server_name()}.ini")
end
