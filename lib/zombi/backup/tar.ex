defmodule Zombi.Backup.Tar do
  @moduledoc """
  Real backup implementation. Flushes the world to disk over RCON (best effort),
  then streams a `tar czf` of the Saves directory and the server `.ini` into the
  configured `:backups_dir`, reporting progress from tar's `--checkpoint` output.

  Progress estimation: tar emits a checkpoint every N records (N = 1000 here).
  Each record is 512 bytes, so after checkpoint `n` roughly `n * N * 512` bytes
  have been read. Dividing by the precomputed total source size gives a percent.
  """

  @behaviour Zombi.Backup

  require Logger

  @checkpoint_records 1000
  @tar_block_size 512
  @checkpoint_re ~r/ZCKPT (\d+)/

  @impl true
  def archive(opts) do
    name = Keyword.fetch!(opts, :name)
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    flush_world()

    base_dir = compose_dir()
    saves_dir = Path.join(base_dir, "server-data/Saves")
    ini_path = Zombi.Workshop.server_ini_path()

    total_bytes = dir_size(saves_dir) + file_size(ini_path)

    backups = backups_dir()
    File.mkdir_p!(backups)
    out_path = Path.join(backups, name)

    relative_saves = Path.relative_to(saves_dir, base_dir)
    relative_ini = Path.relative_to(ini_path, base_dir)

    tar_args = [
      "czf",
      out_path,
      "--checkpoint=#{@checkpoint_records}",
      "--checkpoint-action=echo=ZCKPT %u",
      "-C",
      base_dir,
      relative_saves,
      relative_ini
    ]

    case run_tar(tar_args, total_bytes, on_progress) do
      0 ->
        on_progress.(100)
        {:ok, %{path: out_path, size: file_size(out_path)}}

      status ->
        {:error, "tar exited #{status}"}
    end
  end

  @doc """
  Pure progress math: given tar's checkpoint number, the records-per-checkpoint,
  and the total source size in bytes, returns an integer percent in `0..100`.

  When `total_bytes` is 0 there is nothing to do, so we report 100.
  """
  @spec percent_for(non_neg_integer, pos_integer, non_neg_integer) :: 0..100
  def percent_for(_checkpoint_no, _checkpoint_records, 0), do: 100

  def percent_for(checkpoint_no, checkpoint_records, total_bytes) do
    bytes = checkpoint_no * checkpoint_records * @tar_block_size

    (bytes * 100 / total_bytes)
    |> round()
    |> max(0)
    |> min(100)
  end

  # --- internals ---

  # Best-effort flush of the world to disk. The server may be down, so any
  # error or exception is swallowed.
  defp flush_world do
    Zombi.Rcon.command("save")
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  # Spawn tar through /bin/sh so we can redirect stderr to stdout: GNU tar's
  # --checkpoint-action=echo writes to stderr, and :stderr_to_stdout is not a
  # Port option.
  defp run_tar(tar_args, total_bytes, on_progress) do
    command = "tar " <> Enum.map_join(tar_args, " ", &shell_quote/1) <> " 2>&1"

    port =
      Port.open(
        {:spawn_executable, "/bin/sh"},
        [:binary, :exit_status, {:line, 4096}, args: ["-c", command]]
      )

    collect(port, total_bytes, on_progress, -1, "")
  end

  defp collect(port, total_bytes, on_progress, last_percent, partial) do
    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        collect(port, total_bytes, on_progress, last_percent, partial <> chunk)

      {^port, {:data, {:eol, chunk}}} ->
        last =
          handle_line(partial <> chunk, total_bytes, on_progress, last_percent)

        collect(port, total_bytes, on_progress, last, "")

      {^port, {:exit_status, status}} ->
        status
    end
  end

  defp handle_line(line, total_bytes, on_progress, last_percent) do
    case Regex.run(@checkpoint_re, line, capture: :all_but_first) do
      [n] ->
        percent = percent_for(String.to_integer(n), @checkpoint_records, total_bytes)

        if percent != last_percent do
          on_progress.(percent)
          percent
        else
          last_percent
        end

      nil ->
        last_percent
    end
  end

  # Recursively sums the size of every regular file under `dir`. Missing dirs
  # contribute 0 (nothing to back up yet).
  defp dir_size(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce(entries, 0, fn entry, acc ->
          path = Path.join(dir, entry)

          case File.stat(path) do
            {:ok, %File.Stat{type: :directory}} -> acc + dir_size(path)
            {:ok, %File.Stat{type: :regular, size: size}} -> acc + size
            _ -> acc
          end
        end)

      {:error, _} ->
        0
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp shell_quote(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end

  defp compose_dir, do: Application.fetch_env!(:zombi, :compose_dir)
  defp backups_dir, do: Application.fetch_env!(:zombi, :backups_dir)
end
