defmodule Zombi.SystemStatsTest do
  use ExUnit.Case, async: true

  alias Zombi.SystemStats

  describe "memory_used/2" do
    test "prefers available_memory" do
      assert SystemStats.memory_used([available_memory: 400, free_memory: 100], 1000) == 600
    end

    test "falls back to free_memory" do
      assert SystemStats.memory_used([free_memory: 100], 1000) == 900
    end

    test "nil when neither present" do
      assert SystemStats.memory_used([], 1000) == nil
    end
  end

  describe "build_memory/2" do
    test "computes percent" do
      assert SystemStats.build_memory(1000, 250) == %{total: 1000, used: 250, percent: 25.0}
    end

    test "nil when data missing" do
      assert SystemStats.build_memory(nil, 250) == nil
      assert SystemStats.build_memory(1000, nil) == nil
    end
  end

  describe "format_bytes/1" do
    test "formats to the right unit" do
      assert SystemStats.format_bytes(1_073_741_824) == "1.0 GiB"
      assert SystemStats.format_bytes(1_572_864) == "1.5 MiB"
      assert SystemStats.format_bytes(512) == "512 B"
    end
  end
end
