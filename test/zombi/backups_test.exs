defmodule Zombi.BackupsTest do
  use ExUnit.Case, async: false

  alias Zombi.Backups
  alias Zombi.Backups.Runner

  setup %{} = context do
    # ETS rows are not in the SQL sandbox; clean them manually.
    Backups.read_backups!() |> Enum.each(&Backups.delete_backup!/1)

    if tmp_dir = context[:tmp_dir] do
      original = Application.fetch_env!(:zombi, :backups_dir)
      Application.put_env(:zombi, :backups_dir, tmp_dir)
      on_exit(fn -> Application.put_env(:zombi, :backups_dir, original) end)
    end

    :ok
  end

  test "start_backup! creates a preparing row with the given name" do
    row = Backups.start_backup!(%{name: "b.tar.gz"})

    assert row.status == :preparing
    assert row.name == "b.tar.gz"
    assert row.percent == 0
  end

  test "update_backup! reflects in get_backup!" do
    row = Backups.start_backup!(%{name: "b.tar.gz"})
    Backups.update_backup!(row, %{percent: 50, status: :archiving})

    reloaded = Backups.get_backup!(row.id)
    assert reloaded.percent == 50
    assert reloaded.status == :archiving
  end

  @tag :tmp_dir
  test "refresh_backups! picks up an untracked .tar.gz", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "found.tar.gz")
    File.write!(path, "some archive bytes")
    expected_size = File.stat!(path).size

    backups = Backups.refresh_backups!()

    found = Enum.find(backups, &(&1.name == "found.tar.gz"))
    assert found
    assert found.status == :done
    assert found.percent == 100
    assert found.size == expected_size
    assert found.path == path
  end

  @tag :tmp_dir
  test "delete_backup! removes the row and the file from disk", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "todelete.tar.gz")
    File.write!(path, "bytes")
    assert File.exists?(path)

    [row] = Backups.refresh_backups!()
    Backups.delete_backup!(row)

    refute File.exists?(path)
    assert Backups.read_backups!() == []
  end

  @tag :tmp_dir
  test "Runner reaches :done via the Fake impl" do
    row = Backups.start_backup!(%{name: "run.tar.gz"})
    Runner.subscribe(row.id)

    {:ok, _pid} = Runner.start(row)

    assert_receive {:backup_progress, %{id: id, status: :done, percent: 100}}, 2000
    assert id == row.id

    done = Backups.get_backup!(row.id)
    assert done.status == :done
    assert done.percent == 100
    assert is_binary(done.path)
    assert done.size > 0
  end
end
