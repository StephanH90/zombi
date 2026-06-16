defmodule Zombi.Stats.Player do
  use Ash.Resource, otp_app: :zombi, domain: Zombi.Stats, data_layer: AshSqlite.DataLayer

  sqlite do
    table "players"
    repo Zombi.Repo
  end

  actions do
    defaults [:read]

    create :record do
      description "Upsert a player's latest stats, keyed by username."
      upsert? true
      upsert_identity :unique_username
      accept [:username, :hours_survived, :zombie_kills, :health]
      change set_attribute(:online, true)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    update :mark_offline do
      description "Flag a player as no longer connected."
      change set_attribute(:online, false)
    end

    action :ingest, :map do
      description "Ingest a stats sample: upsert online players, snapshot them, and log join/leave events."
      argument :players, {:array, :map}, allow_nil?: false
      run Zombi.Stats.Player.Ingest
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :username, :string do
      allow_nil? false
      public? true
    end

    attribute :hours_survived, :float do
      public? true
    end

    attribute :zombie_kills, :integer do
      public? true
    end

    attribute :health, :float do
      public? true
    end

    attribute :last_seen_at, :utc_datetime_usec do
      public? true
    end

    attribute :online, :boolean do
      allow_nil? false
      default false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_username, [:username]
  end
end
