defmodule Zombi.GameServerTest do
  use ExUnit.Case, async: true

  alias Zombi.GameServer

  describe "parse_version/1" do
    test "extracts version and date from a log line" do
      log = """
      LOG  : General      f:0 st:1> version=42.19.0 1aa820d7bb66c4e55 2026-06-01 09:40:02 (ZB) demo=false
      """

      assert GameServer.parse_version(log) == {:ok, %{version: "42.19.0", date: "2026-06-01"}}
    end

    test "uses the most recent match" do
      log = """
      version=42.18.0 hashA 2026-05-01 09:00:00 (ZB)
      version=42.19.0 hashB 2026-06-01 09:40:02 (ZB)
      """

      assert {:ok, %{version: "42.19.0"}} = GameServer.parse_version(log)
    end

    test "errors when no version line present" do
      assert {:error, _} = GameServer.parse_version("no version here")
    end
  end
end
