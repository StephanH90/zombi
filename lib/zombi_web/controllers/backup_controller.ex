defmodule ZombiWeb.BackupController do
  use ZombiWeb, :controller

  def download(conn, %{"id" => id}) do
    backup = Zombi.Backups.read_backups!() |> Enum.find(&(&1.id == id))

    if backup && backup.status == :done && File.exists?(backup.path) do
      send_download(conn, {:file, backup.path}, filename: backup.name)
    else
      conn |> put_status(:not_found) |> text("Backup not found")
    end
  end
end
