defmodule Zombi.ModConfig.File do
  @moduledoc """
  File-backed `Zombi.ModConfig` reading and writing the active server `.ini`.

  Only the `WorkshopItems=` and `Mods=` lines are touched; every other line is
  preserved byte-for-byte. Writes are atomic (temp file in the same dir, then
  rename).
  """

  @behaviour Zombi.ModConfig

  alias Zombi.Workshop

  @impl true
  def read_mods do
    case File.read(Workshop.server_ini_path()) do
      {:ok, content} ->
        {:ok,
         %{
           workshop_ids: Workshop.parse_workshop_items(content),
           mod_ids: Workshop.parse_mods_line(content)
         }}

      {:error, reason} ->
        {:error, "could not read server ini: #{:file.format_error(reason)}"}
    end
  end

  @impl true
  def write_mods(%{workshop_ids: workshop_ids, mod_ids: mod_ids}) do
    path = Workshop.server_ini_path()

    with {:ok, content} <- File.read(path),
         updated = put_mods_lines(content, workshop_ids, mod_ids),
         tmp = path <> ".tmp",
         :ok <- File.write(tmp, updated),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} when is_atom(reason) ->
        {:error, "could not write server ini: #{:file.format_error(reason)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def put_mods_lines(content, workshop_ids, mod_ids) do
    workshop_line = "WorkshopItems=" <> (workshop_ids |> Enum.uniq() |> Enum.join(";"))
    mods_line = "Mods=" <> (mod_ids |> Enum.uniq() |> Enum.join(";"))

    content
    |> replace_or_append(~r/^WorkshopItems=.*$/m, workshop_line)
    |> replace_or_append(~r/^Mods=.*$/m, mods_line)
  end

  defp replace_or_append(content, regex, line) do
    if Regex.match?(regex, content) do
      Regex.replace(regex, content, line)
    else
      ensure_trailing_newline(content) <> line <> "\n"
    end
  end

  defp ensure_trailing_newline(""), do: ""

  defp ensure_trailing_newline(content) do
    if String.ends_with?(content, "\n"), do: content, else: content <> "\n"
  end
end
