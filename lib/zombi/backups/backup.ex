defmodule Zombi.Backups.Backup do
  @moduledoc """
  Tracks a single backup run. Stored in ETS (shared across processes) so the
  Runner Task and LiveViews can all read/write the same rows without a DB.
  """
  use Ash.Resource,
    otp_app: :zombi,
    domain: Zombi.Backups,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? false
  end

  actions do
    defaults [:read]

    create :start do
      description "Begin tracking a backup run (status :preparing)."
      accept []
      argument :name, :string, allow_nil?: true

      change set_attribute(:status, :preparing)
      change set_attribute(:phase, "Preparing")
      change set_attribute(:percent, 0)

      change fn changeset, _context ->
        name = Ash.Changeset.get_argument(changeset, :name) || "backup.tar.gz"
        Ash.Changeset.change_attribute(changeset, :name, name)
      end
    end

    update :progress do
      description "Update progress/status of a running backup."
      accept [:phase, :percent, :status, :path, :size]
      require_atomic? false
    end

    destroy :destroy do
      description "Delete the row and remove the archive file from disk."
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          case changeset.data.path do
            path when is_binary(path) -> File.rm(path)
            _ -> :ok
          end

          changeset
        end)
      end
    end

    action :refresh, {:array, :struct} do
      description "Scan :backups_dir and add rows for any untracked .tar.gz files."
      constraints items: [instance_of: __MODULE__]
      run Zombi.Backups.Backup.Refresh
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:preparing, :archiving, :done, :failed]
      default :preparing
      public? true
    end

    attribute :phase, :string do
      public? true
    end

    attribute :percent, :integer do
      default 0
      public? true
    end

    attribute :size, :integer do
      public? true
    end

    attribute :path, :string do
      public? true
    end

    timestamps()
  end
end
