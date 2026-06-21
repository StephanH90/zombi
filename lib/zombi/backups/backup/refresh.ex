defmodule Zombi.Backups.Backup.Refresh do
  @moduledoc """
  Generic action implementation for `:refresh`. Scans the configured
  `:backups_dir` for `*.tar.gz` files that aren't already tracked and creates a
  `:done` row for each, then returns the full current list of backups.
  """
  use Ash.Resource.Actions.Implementation

  alias Zombi.Backups.Backup

  @impl true
  def run(_input, _opts, _context) do
    dir = Application.fetch_env!(:zombi, :backups_dir)
    existing = Ash.read!(Backup)
    tracked_names = MapSet.new(existing, & &1.name)

    dir
    |> list_archives()
    |> Enum.reject(&MapSet.member?(tracked_names, &1))
    |> Enum.each(fn name ->
      path = Path.join(dir, name)

      case File.stat(path) do
        {:ok, %{size: size}} ->
          Backup
          |> Ash.Changeset.for_create(:start, %{name: name})
          |> Ash.create!()
          |> Ash.Changeset.for_update(:progress, %{
            status: :done,
            phase: "Done",
            percent: 100,
            path: path,
            size: size
          })
          |> Ash.update!()

        {:error, _} ->
          :ok
      end
    end)

    {:ok, Ash.read!(Backup)}
  end

  defp list_archives(dir) do
    case File.ls(dir) do
      {:ok, files} -> Enum.filter(files, &String.ends_with?(&1, ".tar.gz"))
      {:error, _} -> []
    end
  end
end
