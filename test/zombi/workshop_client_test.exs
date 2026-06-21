defmodule Zombi.WorkshopClientTest do
  use ExUnit.Case, async: true

  alias Zombi.WorkshopClient.Steam

  describe "parse_mod_ids/1" do
    test "extracts title and deduped mod ids in order from a real-ish workshop page" do
      html =
        File.read!(Path.join([__DIR__, "..", "support", "fixtures", "workshop_page.html"]))

      assert Steam.parse_mod_ids(html) == %{
               title: "Brita's Weapon Pack",
               mod_ids: ["Brita", "Brita_2"]
             }
    end

    test "falls back to the <title> tag (stripping the Steam prefix) when no item title div" do
      html = """
      <html><head><title>Steam Workshop::Some Mod</title></head>
      <body><div>Mod ID: SomeMod</div></body></html>
      """

      assert Steam.parse_mod_ids(html) == %{title: "Some Mod", mod_ids: ["SomeMod"]}
    end

    test "returns empty mod_ids when none are present" do
      html = """
      <div class="workshopItemTitle">No Mods Here</div>
      <div>Just a description with no mod identifiers.</div>
      """

      assert Steam.parse_mod_ids(html) == %{title: "No Mods Here", mod_ids: []}
    end

    test "defaults title to empty string when neither title source is present" do
      assert Steam.parse_mod_ids("<div>Mod ID: Lonely</div>") == %{
               title: "",
               mod_ids: ["Lonely"]
             }
    end
  end
end
