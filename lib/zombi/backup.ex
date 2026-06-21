defmodule Zombi.Backup do
  @moduledoc """
  Archiving primitive for one-click backups: tars the Project Zomboid savegame
  (`server-data/Saves`) plus the server config `.ini` into a timestamped
  `.tar.gz` under the configured `:backups_dir`, reporting live progress as an
  integer percent.

  This is the archiving step only. A separate Runner drives PubSub/state and
  calls `archive/1`. The implementation is swappable via config
  (`config :zombi, backup_runner: <impl>`): the real `Zombi.Backup.Tar` on the
  gameserver host, `Zombi.Backup.Fake` in dev/test.
  """

  @doc """
  Archives the savegame and server config.

  Options:

    * `:name` — the target filename, e.g. `"backup-2026-06-21-1430.tar.gz"`.
    * `:on_progress` — a 1-arity function called with an integer percent
      (`0..100`) as work proceeds.

  Returns `{:ok, %{path: path, size: bytes}}` or `{:error, reason}`.
  """
  @callback archive(opts :: keyword) ::
              {:ok, %{path: String.t(), size: non_neg_integer}} | {:error, term}

  @doc "The configured backup implementation."
  def impl, do: Application.get_env(:zombi, :backup_runner, Zombi.Backup.Tar)
end
