defmodule Zombi.Release do
  @moduledoc """
  Release tasks, e.g. running migrations from a built release.

  Run on the live node from the deploy script:

      bin/zombi rpc "Zombi.Release.migrate()"
  """
  @app :zombi

  def migrate do
    for repo <- repos() do
      Ecto.Migrator.run(repo, :up, all: true)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
