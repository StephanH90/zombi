defmodule Zombi.ModsTest do
  # async: false because these mutate the shared Zombi.ModConfig.Fake Agent.
  use ExUnit.Case, async: false

  alias Zombi.Mods

  setup do
    # Reset the Fake agent to its seed before each test so ordering is irrelevant.
    Zombi.ModConfig.write_mods(%{
      workshop_ids: ["2618213077", "2772575623"],
      mod_ids: ["damnlib", "ECTO1", "Brita_2"]
    })

    :ok
  end

  describe "current_mods/0" do
    test "returns the configured workshop_ids and mod_ids as a flat map" do
      assert %{
               workshop_ids: ["2618213077", "2772575623"],
               mod_ids: ["damnlib", "ECTO1", "Brita_2"]
             } = Mods.current_mods!()
    end
  end

  describe "list_mods/0" do
    test "returns one Mod struct per workshop id" do
      mods = Mods.list_mods!()

      assert [%Mods.Mod{}, %Mods.Mod{}] = mods
      assert Enum.map(mods, & &1.workshop_id) == ["2618213077", "2772575623"]
    end
  end

  describe "resolve_link/1" do
    test "resolves a full workshop url to workshop info via the client" do
      assert %{
               workshop_id: "123",
               title: "Fake Mod 123",
               mod_ids: ["FakeModA", "FakeModB"]
             } =
               Mods.resolve_link!("https://steamcommunity.com/sharedfiles/filedetails/?id=123")
    end

    test "resolves a bare id" do
      assert %{workshop_id: "456", mod_ids: ["FakeModA", "FakeModB"]} =
               Mods.resolve_link!("456")
    end
  end

  describe "activate_mods/2" do
    test "dedupes, persists to the config, and returns the payload" do
      payload = Mods.activate_mods!(["111", "111", "222"], ["A", "A", "B"])

      assert payload == %{workshop_ids: ["111", "222"], mod_ids: ["A", "B"]}

      # Persisted: a subsequent read reflects the activation.
      assert %{workshop_ids: ["111", "222"], mod_ids: ["A", "B"]} = Mods.current_mods!()

      assert {:ok, %{workshop_ids: ["111", "222"], mod_ids: ["A", "B"]}} =
               Zombi.ModConfig.read_mods()
    end
  end
end
