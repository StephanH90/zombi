defmodule Zombi.ModConfig do
  @moduledoc """
  Reads and writes the active Project Zomboid server `.ini` mod lists
  (the `WorkshopItems=` and `Mods=` lines).

  The concrete implementation is config-driven via `config :zombi, mod_config:`,
  defaulting to `Zombi.ModConfig.File`. Tests and dev use `Zombi.ModConfig.Fake`.
  """

  @callback read_mods() ::
              {:ok, %{workshop_ids: [String.t()], mod_ids: [String.t()]}} | {:error, term}
  @callback write_mods(%{workshop_ids: [String.t()], mod_ids: [String.t()]}) ::
              :ok | {:error, term}

  @doc "The configured implementation module."
  def impl, do: Application.get_env(:zombi, :mod_config, Zombi.ModConfig.File)

  @doc "Delegates to the configured implementation's `read_mods/0`."
  def read_mods, do: impl().read_mods()

  @doc "Delegates to the configured implementation's `write_mods/1`."
  def write_mods(mods), do: impl().write_mods(mods)
end
