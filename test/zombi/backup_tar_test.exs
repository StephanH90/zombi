defmodule Zombi.Backup.TarTest do
  use ExUnit.Case, async: true

  alias Zombi.Backup.Tar

  describe "percent_for/3" do
    test "is 0 at the first (zero) checkpoint" do
      assert Tar.percent_for(0, 1000, 1_000_000) == 0
    end

    test "increases monotonically as the checkpoint number rises" do
      total = 50_000_000

      percents =
        for n <- 0..100 do
          Tar.percent_for(n, 1000, total)
        end

      assert percents == Enum.sort(percents)
      assert Enum.uniq(percents) != [0]
    end

    test "clamps at 100 when bytes exceed the total" do
      assert Tar.percent_for(1_000_000, 1000, 1000) == 100
    end

    test "is 100 when there is nothing to do (total is zero)" do
      assert Tar.percent_for(5, 1000, 0) == 100
    end
  end
end
