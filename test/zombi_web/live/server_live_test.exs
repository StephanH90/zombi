defmodule ZombiWeb.ServerLiveTest do
  use ZombiWeb.ConnCase

  import Phoenix.LiveViewTest

  defp auth_header(conn) do
    %{username: user, password: pass} = Map.new(Application.fetch_env!(:zombi, :basic_auth))
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, pass))
  end

  test "rejects requests without credentials", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert conn.status == 401
  end

  test "rejects requests with wrong password", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("admin", "nope"))
      |> get(~p"/")

    assert conn.status == 401
  end

  test "renders the restart button when authenticated", %{conn: conn} do
    {:ok, view, _html} = conn |> auth_header() |> live(~p"/")
    assert has_element?(view, "#restart-button")
  end
end
