defmodule ZombiWeb.BackupLiveTest do
  use ZombiWeb.ConnCase

  import Phoenix.LiveViewTest

  defp auth_header(conn) do
    %{username: user, password: pass} = Map.new(Application.fetch_env!(:zombi, :basic_auth))
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, pass))
  end

  # ETS rows persist across tests in the VM, so clear them before each test.
  setup do
    Zombi.Backups.read_backups!() |> Enum.each(&Zombi.Backups.delete_backup!/1)
    :ok
  end

  test "rejects requests without credentials", %{conn: conn} do
    conn = get(conn, ~p"/backup")
    assert conn.status == 401
  end

  test "renders the backup tab and create button when authenticated", %{conn: conn} do
    {:ok, view, html} = conn |> auth_header() |> live(~p"/backup")
    assert has_element?(view, "#create-backup")
    assert html =~ "Backup"
    assert html =~ "Create backup"
  end

  test "creating a backup runs to completion and offers a download", %{conn: conn} do
    {:ok, view, _html} = conn |> auth_header() |> live(~p"/backup")

    render_click(element(view, "#create-backup"))

    # The Fake runs in a supervised Task with small sleeps. Poll the rendered
    # view until the row reaches the "Done" badge and a Download link appears.
    assert wait_until(fn ->
             html = render(view)
             html =~ "Done" and has_element?(view, "a[href*='/download']")
           end)

    assert has_element?(view, "a[download]")
  end

  test "deleting a backup removes it from the list", %{conn: conn} do
    {:ok, view, _html} = conn |> auth_header() |> live(~p"/backup")

    render_click(element(view, "#create-backup"))
    assert wait_until(fn -> render(view) =~ "Done" end)

    [row] = Zombi.Backups.read_backups!()
    render_click(element(view, "button[phx-value-id='#{row.id}']"))

    assert wait_until(fn -> render(view) =~ "No backups yet." end)
    assert Zombi.Backups.read_backups!() == []
  end

  # Polls fun until it returns truthy or the deadline passes.
  defp wait_until(fun, attempts \\ 50)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end
end
