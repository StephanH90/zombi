defmodule Zombi.SystemStats do
  @moduledoc """
  A single sample of host CPU (per core) and memory usage, read from OTP's
  `:os_mon` (`:cpu_sup`, `:memsup`) — the same source the Phoenix LiveDashboard
  uses.

  `:cpu_sup.util/1` reports utilization since the previous call, so it must be
  called from a single place (see `Zombi.StatsCollector`) to avoid concurrent
  callers resetting each other's counters.
  """

  @doc "One sample: `%{cpu: [%{id, percent}], memory: %{used, total, percent} | nil}`."
  def sample do
    %{cpu: cpu_cores(), memory: memory()}
  end

  defp cpu_cores do
    :cpu_sup.util([:per_cpu])
    |> Enum.map(fn {id, busy, _non_busy, _misc} -> %{id: id, percent: Float.round(busy * 1.0, 1)} end)
  rescue
    _ -> []
  end

  defp memory do
    data = :memsup.get_system_memory_data()
    total = data[:total_memory] || data[:system_total_memory]
    build_memory(total, memory_used(data, total))
  rescue
    _ -> nil
  end

  @doc false
  def memory_used(data, total) do
    cond do
      data[:available_memory] -> total && total - data[:available_memory]
      data[:free_memory] -> total && total - data[:free_memory]
      true -> nil
    end
  end

  @doc false
  def build_memory(nil, _used), do: nil
  def build_memory(_total, nil), do: nil

  def build_memory(total, used) do
    %{total: total, used: used, percent: Float.round(used / total * 100, 1)}
  end

  @doc "Human-readable bytes, e.g. `7.6 GiB`."
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GiB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MiB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KiB"
      true -> "#{bytes} B"
    end
  end

  def format_bytes(_), do: "—"
end
