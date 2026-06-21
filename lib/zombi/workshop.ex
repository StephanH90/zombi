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

  @doc """
  Returns `{:ok, mods}` listing every subscribed mod with its installed and
  latest Steam versions, sorted by title. Each entry:
  `%{id, title, installed_at, latest_at, up_to_date?}` (datetimes are nil when
  unknown).
  """
  def all_mods do
    with {:ok, ids} <- subscribed_ids(),
         {:ok, local} <- local_versions(),
         {:ok, remote} <- remote_details(ids) do
      mods =
        Enum.map(ids, fn id ->
          details = remote[id]
          installed = Map.get(local, id, 0)
          latest = (details && details.time_updated) || 0

          %{
            id: id,
            title: (details && details.title) || id,
            installed_at: unix_to_datetime(installed),
            latest_at: unix_to_datetime(latest),
            up_to_date?: latest <= installed
          }
        end)

      {:ok, Enum.sort_by(mods, &String.downcase(&1.title))}
    end
  end

  defp unix_to_datetime(0), do: nil
  defp unix_to_datetime(ts), do: DateTime.from_unix!(ts)

  @doc "Steam Workshop page URL for a published file id."
  def workshop_url(id), do: "https://steamcommunity.com/sharedfiles/filedetails/?id=#{id}"

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
      {:ok, content} ->
        {:ok, parse_acf(content)}

      {:error, reason} ->
        {:error, "could not read workshop manifest: #{:file.format_error(reason)}"}
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
  def parse_mods_line(ini_content) do
    case Regex.run(~r/^Mods=(.*)$/m, ini_content, capture: :all_but_first) do
      [list] ->
        list
        |> String.split(";", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      nil ->
        []
    end
  end

  @doc """
  Extracts the numeric published-file id from a Steam Workshop link, or accepts a
  bare id. Returns `{:ok, id}` or `{:error, reason}`.
  """
  def url_to_id(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      Regex.match?(~r/^\d+$/, trimmed) ->
        {:ok, trimmed}

      match = Regex.run(~r/[?&]id=(\d+)/, trimmed, capture: :all_but_first) ->
        [id] = match
        {:ok, id}

      true ->
        {:error, "could not find a workshop id in #{inspect(input)}"}
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

  @doc "Absolute path to the active server config `.ini`."
  def server_ini_path,
    do: Path.join(compose_dir(), "server-data/Server/#{server_name()}.ini")
end
