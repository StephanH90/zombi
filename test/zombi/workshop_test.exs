defmodule Zombi.WorkshopTest do
  use ExUnit.Case, async: true

  alias Zombi.Workshop

  describe "parse_workshop_items/1" do
    test "extracts the semicolon-separated WorkshopItems list" do
      ini = """
      Mods=damnlib;ECTO1
      WorkshopItems=2618213077;2772575623;2478247379
      Public=true
      """

      assert Workshop.parse_workshop_items(ini) == ["2618213077", "2772575623", "2478247379"]
    end

    test "returns [] when no WorkshopItems line" do
      assert Workshop.parse_workshop_items("Public=true\n") == []
    end

    test "ignores trailing empty entries" do
      assert Workshop.parse_workshop_items("WorkshopItems=111;222;") == ["111", "222"]
    end
  end

  describe "parse_mods_line/1" do
    test "extracts the semicolon-separated Mods list" do
      ini = """
      Mods=damnlib;ECTO1;Brita_2
      WorkshopItems=2618213077
      """

      assert Workshop.parse_mods_line(ini) == ["damnlib", "ECTO1", "Brita_2"]
    end

    test "returns [] when no Mods line" do
      assert Workshop.parse_mods_line("Public=true\n") == []
    end

    test "ignores trailing empty entries" do
      assert Workshop.parse_mods_line("Mods=a;b;") == ["a", "b"]
    end
  end

  describe "url_to_id/1" do
    test "extracts id from a full workshop url" do
      assert Workshop.url_to_id(
               "https://steamcommunity.com/sharedfiles/filedetails/?id=2618213077"
             ) == {:ok, "2618213077"}
    end

    test "extracts id when extra query params follow" do
      assert Workshop.url_to_id(
               "https://steamcommunity.com/sharedfiles/filedetails/?id=123&searchtext=foo"
             ) == {:ok, "123"}
    end

    test "accepts a bare numeric id" do
      assert Workshop.url_to_id("2618213077") == {:ok, "2618213077"}
    end

    test "returns error for input with no id" do
      assert {:error, _} = Workshop.url_to_id("https://steamcommunity.com/app/108600")
    end
  end

  describe "parse_acf/1" do
    test "maps each workshop id to its timeupdated" do
      acf = """
      "AppWorkshop"
      {
        "appid"  "108600"
        "WorkshopItemsInstalled"
        {
          "2478247379"
          {
            "size"  "15275972"
            "timeupdated"  "1768504412"
            "manifest"  "5158730645719318309"
          }
          "2618213077"
          {
            "size"  "30719781"
            "timeupdated"  "1781027574"
            "manifest"  "6557046071529781246"
          }
        }
      }
      """

      assert Workshop.parse_acf(acf) == %{
               "2478247379" => 1_768_504_412,
               "2618213077" => 1_781_027_574
             }
    end

    test "keeps the newest timeupdated when an id appears twice" do
      acf = """
      "111" { "timeupdated" "100" }
      "111" { "timeupdated" "200" }
      """

      assert Workshop.parse_acf(acf) == %{"111" => 200}
    end
  end
end
