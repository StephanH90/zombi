defmodule Zombi.Repo do
  use AshSqlite.Repo,
    otp_app: :zombi
end
