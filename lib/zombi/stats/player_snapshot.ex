defmodule Zombi.Stats.PlayerSnapshot do
  use Ash.Resource, otp_app: :zombi, domain: Zombi.Stats, data_layer: AshSqlite.DataLayer

  sqlite do
    table "player_snapshots"
    repo Zombi.Repo
  end

  actions do
    defaults [:read, create: [:username, :zombie_kills, :hours_survived]]

    read :for_player do
      description "Time-ordered snapshots for one player, for graphing."
      argument :username, :string, allow_nil?: false
      filter expr(username == ^arg(:username))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :username, :string do
      allow_nil? false
      public? true
    end

    attribute :zombie_kills, :integer do
      public? true
    end

    attribute :hours_survived, :float do
      public? true
    end

    timestamps()
  end
end
