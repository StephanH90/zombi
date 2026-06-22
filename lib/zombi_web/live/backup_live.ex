defmodule ZombiWeb.BackupLive do
  use ZombiWeb, :live_view

  alias Zombi.Backups
  alias Zombi.Backups.Runner

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Runner.subscribe_list()
      Backups.refresh_backups!()
    end

    {:ok, assign(socket, :backups, load_backups())}
  end

  def handle_event("create", _params, socket) do
    name =
      "backup-" <> Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d-%H%M%S") <> ".tar.gz"

    row = Backups.start_backup!(%{name: name})
    Runner.subscribe(row.id)
    Runner.start(row)

    {:noreply,
     socket
     |> assign(:backups, load_backups())
     |> put_flash(:info, "Backup started.")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.backups, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      row ->
        Backups.delete_backup!(row)

        {:noreply,
         socket
         |> assign(:backups, load_backups())
         |> put_flash(:info, "Backup deleted.")}
    end
  end

  def handle_info({:backup_progress, p}, socket) do
    socket =
      if p.status in [:done, :failed] do
        assign(socket, :backups, load_backups())
      else
        backups =
          Enum.map(socket.assigns.backups, fn b ->
            if b.id == p.id do
              %{b | status: p.status, phase: p.phase, percent: p.percent}
            else
              b
            end
          end)

        assign(socket, :backups, backups)
      end

    {:noreply, socket}
  end

  def handle_info({:backups_changed}, socket) do
    {:noreply, assign(socket, :backups, load_backups())}
  end

  defp load_backups do
    Backups.read_backups!()
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp in_progress?(%{status: status}), do: status in [:preparing, :archiving]

  defp humanize_bytes(nil), do: "—"
  defp humanize_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp humanize_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp humanize_bytes(bytes) when bytes < 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  end

  defp humanize_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
  end

  defp status_badge_class(:done), do: "badge badge-success"
  defp status_badge_class(:failed), do: "badge badge-error"
  defp status_badge_class(_), do: "badge badge-info"

  defp status_label(:preparing), do: "Preparing"
  defp status_label(:archiving), do: "Archiving"
  defp status_label(:done), do: "Done"
  defp status_label(:failed), do: "Failed"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <Layouts.tabs active={:backup} />
      <div class="flex flex-col gap-6 py-10">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">Backups</h1>
            <p class="text-sm text-base-content/60">
              Archive the world save and download it. One backup at a time.
            </p>
          </div>
          <.button id="create-backup" variant="primary" phx-click="create">
            <.icon name="hero-archive-box-arrow-down" class="size-5" /> Create backup
          </.button>
        </div>

        <div
          :for={b <- @backups}
          :if={in_progress?(b)}
          id={"progress-#{b.id}"}
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body gap-2">
            <div class="flex items-center justify-between">
              <span class="font-medium">{b.name}</span>
              <span class="text-sm text-base-content/70">{b.phase} — {b.percent}%</span>
            </div>
            <progress class="progress progress-primary w-full" value={b.percent} max="100">
              {b.percent}%
            </progress>
          </div>
        </div>

        <div :if={@backups == []} class="text-center text-base-content/60 py-8">
          No backups yet.
        </div>

        <div :if={@backups != []} class="overflow-x-auto">
          <.table id="backups" rows={@backups}>
            <:col :let={b} label="Name">{b.name}</:col>
            <:col :let={b} label="Size">{humanize_bytes(b.size)}</:col>
            <:col :let={b} label="Created">
              {local_time(b.inserted_at, @timezone)}
            </:col>
            <:col :let={b} label="Status">
              <span class={status_badge_class(b.status)}>{status_label(b.status)}</span>
            </:col>
            <:action :let={b}>
              <.button
                :if={b.status == :done}
                href={~p"/backups/#{b.id}/download"}
                download
                class="btn btn-sm btn-primary btn-soft"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Download
              </.button>
              <.button
                phx-click="delete"
                phx-value-id={b.id}
                data-confirm="Delete this backup? This removes the file too."
                class="btn btn-sm btn-error btn-soft"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </.button>
            </:action>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
