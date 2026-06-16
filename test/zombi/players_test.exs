defmodule Zombi.PlayersTest do
  use ExUnit.Case, async: true

  alias Zombi.Players

  describe "parse/1" do
    test "zero players" do
      assert Players.parse("Players connected (0): \n") == %{count: 0, names: []}
    end

    test "players with names" do
      body = "Players connected (2): \n-Bob\n-Alice\n"
      assert Players.parse(body) == %{count: 2, names: ["Bob", "Alice"]}
    end

    test "count comes from the parenthetical even if names are absent" do
      assert Players.parse("Players connected (3): \n") == %{count: 3, names: []}
    end

    test "unrecognized body defaults to zero" do
      assert Players.parse("") == %{count: 0, names: []}
    end
  end
end
