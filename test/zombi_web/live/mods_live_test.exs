defmodule ZombiWeb.ModsLiveTest do
  use ZombiWeb.ConnCase

  import Phoenix.LiveViewTest

  defp auth_header(conn) do
    %{username: user, password: pass} = Map.new(Application.fetch_env!(:zombi, :basic_auth))
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, pass))
  end

  defp live_mods(conn) do
    {:ok, view, _html} = conn |> auth_header() |> live(~p"/mods")
    # Await the start_async work kicked off on connected mount.
    render_async(view)
    view
  end

  test "rejects requests without credentials", %{conn: conn} do
    conn = get(conn, ~p"/mods")
    assert conn.status == 401
  end

  test "renders the active workshop ids and mod ids from the fake", %{conn: conn} do
    view = live_mods(conn)

    html = render(view)
    # Seeded workshop ids from ModConfig.Fake.
    assert html =~ "2618213077"
    assert html =~ "2772575623"
    # Seeded mod ids from ModConfig.Fake.
    assert html =~ "damnlib"
    assert html =~ "ECTO1"
    assert html =~ "Brita_2"
  end

  test "looking up a workshop link shows the confirm panel with scraped mod-ids", %{conn: conn} do
    view = live_mods(conn)

    view
    |> form("#add-mod-form",
      add: %{link: "https://steamcommunity.com/sharedfiles/filedetails/?id=999"}
    )
    |> render_submit()

    html = render_async(view)

    assert has_element?(view, "#confirm-add")
    # WorkshopClient.Fake returns these mod ids.
    assert html =~ "FakeModA"
    assert html =~ "FakeModB"
  end

  test "confirming a lookup stages the workshop id and chosen mod-ids", %{conn: conn} do
    view = live_mods(conn)

    view
    |> form("#add-mod-form", add: %{link: "999"})
    |> render_submit()

    render_async(view)

    html =
      view
      |> form("#confirm-add-form", confirm: %{mod_ids: ["FakeModA"]})
      |> render_submit()

    refute has_element?(view, "#confirm-add")
    assert html =~ "999"
    assert html =~ "FakeModA"
  end

  test "clicking Activate flashes success", %{conn: conn} do
    view = live_mods(conn)

    view |> element("#activate-button") |> render_click()
    html = render_async(view)

    assert html =~ "activated"
  end
end
