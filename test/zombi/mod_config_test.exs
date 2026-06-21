defmodule Zombi.ModConfigTest do
  use ExUnit.Case, async: true

  alias Zombi.ModConfig.File, as: ModFile
  alias Zombi.Workshop

  describe "put_mods_lines/3" do
    test "round-trips: replaced lines re-parse to the input lists" do
      ini = """
      Mods=old1;old2
      WorkshopItems=111;222
      Public=true
      """

      out = ModFile.put_mods_lines(ini, ["2618213077", "2772575623"], ["damnlib", "ECTO1"])

      assert Workshop.parse_workshop_items(out) == ["2618213077", "2772575623"]
      assert Workshop.parse_mods_line(out) == ["damnlib", "ECTO1"]
    end

    test "dedupes while preserving first-occurrence order" do
      ini = """
      Mods=x
      WorkshopItems=y
      """

      out =
        ModFile.put_mods_lines(
          ini,
          ["111", "222", "111", "333"],
          ["a", "b", "a", "c"]
        )

      assert Workshop.parse_workshop_items(out) == ["111", "222", "333"]
      assert Workshop.parse_mods_line(out) == ["a", "b", "c"]
    end

    test "appends missing lines when absent" do
      ini = "Public=true\n"

      out = ModFile.put_mods_lines(ini, ["111"], ["a"])

      assert Workshop.parse_workshop_items(out) == ["111"]
      assert Workshop.parse_mods_line(out) == ["a"]
    end

    test "leaves unrelated lines intact" do
      ini = """
      Mods=old
      WorkshopItems=111
      Public=true
      PVP=false
      """

      out = ModFile.put_mods_lines(ini, ["222"], ["b"])

      assert out =~ "Public=true"
      assert out =~ "PVP=false"
    end
  end
end
