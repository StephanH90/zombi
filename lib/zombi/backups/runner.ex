defmodule Zombi.Backups.Runner do
  @moduledoc """
  Drives a backup run: flips the tracked row through its phases, calls the
  configured archiving primitive (`Zombi.Backup.impl/0`), and broadcasts live
  progress over PubSub.

  ## PubSub

  Subscribe to a single backup's progress with `subscribe/1` (topic
  `"backup:<id>"`), which receives:

      {:backup_progress, %{id: id, status: status, phase: phase, percent: percent}}

  Subscribe to the list topic with `subscribe_list/0` (topic `"backups"`), which
  receives `{:backups_changed}` whenever the set of backups changes.
  """

  alias Zombi.Backups

  @list_topic "backups"

  @doc "PubSub topic for a single backup's progress."
  def topic(id), do: "backup:" <> id

  @doc "PubSub topic for changes to the set of backups."
  def list_topic, do: @list_topic

  @doc "Subscribe the calling process to one backup's progress."
  def subscribe(id), do: Phoenix.PubSub.subscribe(Zombi.PubSub, topic(id))

  @doc "Subscribe the calling process to changes in the set of backups."
  def subscribe_list, do: Phoenix.PubSub.subscribe(Zombi.PubSub, @list_topic)

  @doc "Spawn a supervised Task that runs the backup."
  def start(backup) do
    Task.Supervisor.start_child(Zombi.BackupTaskSupervisor, fn -> run(backup) end)
  end

  @doc "Run the backup synchronously (called inside the supervised Task)."
  def run(backup) do
    id = backup.id

    update(id, %{status: :archiving, phase: "Archiving", percent: 0})

    result =
      Zombi.Backup.impl().archive(
        name: backup.name,
        on_progress: fn pct ->
          update(id, %{status: :archiving, phase: "Archiving", percent: pct})
        end
      )

    case result do
      {:ok, %{path: path, size: size}} ->
        update(id, %{status: :done, phase: "Done", percent: 100, path: path, size: size})
        broadcast_list_changed()

      {:error, reason} ->
        update(id, %{status: :failed, phase: "Failed: #{inspect(reason)}"})
        broadcast_list_changed()
    end
  end

  defp update(id, attrs) do
    backup =
      id
      |> Backups.get_backup!()
      |> Backups.update_backup!(attrs)

    broadcast_progress(backup)
    backup
  end

  defp broadcast_progress(backup) do
    Phoenix.PubSub.broadcast(
      Zombi.PubSub,
      topic(backup.id),
      {:backup_progress,
       %{id: backup.id, status: backup.status, phase: backup.phase, percent: backup.percent}}
    )
  end

  defp broadcast_list_changed do
    Phoenix.PubSub.broadcast(Zombi.PubSub, @list_topic, {:backups_changed})
  end
end
