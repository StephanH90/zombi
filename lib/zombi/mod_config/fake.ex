defmodule Zombi.ModConfig.Fake do
  @moduledoc """
  In-memory `Zombi.ModConfig` for dev and tests, backed by a lazily-started
  named `Agent` seeded with believable sample data.
  """

  @behaviour Zombi.ModConfig

  @seed %{
    workshop_ids: ["2618213077", "2772575623"],
    mod_ids: ["damnlib", "ECTO1", "Brita_2"]
  }

  @impl true
  def read_mods do
    ensure_agent()
    {:ok, Agent.get(__MODULE__, & &1)}
  end

  @impl true
  def write_mods(%{workshop_ids: _, mod_ids: _} = mods) do
    ensure_agent()
    Agent.update(__MODULE__, fn _ -> mods end)
    :ok
  end

  defp ensure_agent do
    if Process.whereis(__MODULE__) == nil do
      Agent.start(fn -> @seed end, name: __MODULE__)
    end

    :ok
  end
end
