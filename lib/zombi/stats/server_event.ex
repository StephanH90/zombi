defmodule Zombi.Stats.ServerEvent do
  use Ash.Resource, otp_app: :zombi, domain: Zombi.Stats, data_layer: AshSqlite.DataLayer

  sqlite do
    table "server_events"
    repo Zombi.Repo
  end

  actions do
    defaults [:read, create: [:kind, :username, :note]]

    read :recent do
      description "Most recent events first."
      prepare build(sort: [inserted_at: :desc], limit: 100)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:join, :leave, :death]
    end

    attribute :username, :string do
      public? true
    end

    attribute :note, :string do
      public? true
    end

    timestamps()
  end
end
