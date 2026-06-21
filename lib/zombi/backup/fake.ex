defmodule Zombi.Backup.Fake do
  @moduledoc """
  Fake backup implementation for dev/test. Simulates progress over a few phases
  and writes a tiny real file into `:backups_dir` so the download flow works
  off-host.
  """

  @behaviour Zombi.Backup

  @impl true
  def archive(opts) do
    name = Keyword.get(opts, :name, "backup-fake.tar.gz")
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    on_progress.(25)
    Process.sleep(50)
    on_progress.(50)
    Process.sleep(50)
    on_progress.(100)

    backups = Application.fetch_env!(:zombi, :backups_dir)
    File.mkdir_p!(backups)
    path = Path.join(backups, name)
    File.write!(path, "fake backup")

    {:ok, %{path: path, size: File.stat!(path).size}}
  end
end
