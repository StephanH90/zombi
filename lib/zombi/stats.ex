defmodule Zombi.Stats do
  use Ash.Domain,
    otp_app: :zombi

  resources do
    resource Zombi.Stats.Player do
      define :record_player, action: :record, args: [:username]
      define :mark_player_offline, action: :mark_offline
      define :list_players, action: :read
      define :ingest_sample, action: :ingest, args: [:players]
    end

    resource Zombi.Stats.PlayerSnapshot do
      define :create_snapshot, action: :create
      define :player_history, action: :for_player, args: [:username, :since]
    end

    resource Zombi.Stats.ServerEvent do
      define :log_event, action: :create
      define :recent_events, action: :recent
    end
  end
end
