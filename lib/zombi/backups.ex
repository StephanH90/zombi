defmodule Zombi.Backups do
  @moduledoc """
  Domain for tracking backup runs. Rows live in ETS (see `Zombi.Backups.Backup`)
  and the `Zombi.Backups.Runner` drives the archiving primitive while updating
  these rows and broadcasting progress over PubSub.
  """
  use Ash.Domain, otp_app: :zombi

  resources do
    resource Zombi.Backups.Backup do
      define :read_backups, action: :read
      define :start_backup, action: :start
      define :update_backup, action: :progress
      define :refresh_backups, action: :refresh
      define :delete_backup, action: :destroy
      define :get_backup, action: :read, get_by: :id
    end
  end
end
