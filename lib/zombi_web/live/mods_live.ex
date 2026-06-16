defmodule ZombiWeb.ModsLive do
  use ZombiWeb, :live_view

  alias Zombi.Workshop

  def mount(_params, _session, socket) do
    socket = assign(socket, mods: :loading, game: :loading)
    socket = if connected?(socket), do: load(socket), else: socket
    {:ok, socket}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> assign(mods: :loading, game: :loading) |> load()}
  end

  def handle_async(:mods, {:ok, result}, socket), do: {:noreply, assign(socket, :mods, result)}
  def handle_async(:mods, {:exit, r}, socket), do: {:noreply, assign(socket, :mods, {:error, inspect(r)})}
  def handle_async(:game, {:ok, result}, socket), do: {:noreply, assign(socket, :game, result)}
  def handle_async(:game, {:exit, r}, socket), do: {:noreply, assign(socket, :game, {:error, inspect(r)})}

  defp load(socket) do
    socket
    |> start_async(:mods, &Workshop.all_mods/0)
    |> start_async(:game, &Zombi.GameServer.version/0)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <Layouts.tabs active={:mods} />
      <div class="flex flex-col gap-6 py-10">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold">Mods &amp; Version</h1>
          <button class="btn btn-sm" phx-click="refresh">Refresh</button>
        </div>

        <.game_card game={@game} />
        <.mods_table mods={@mods} />
      </div>
    </Layouts.app>
    """
  end

  attr :game, :any, required: true

  defp game_card(%{game: {:ok, %{version: version, date: date}}} = assigns) do
    assigns = assign(assigns, version: version, date: date)

    ~H"""
    <div class="card bg-base-200 p-4">
      <h2 class="font-semibold mb-2">Game version</h2>
      <p>
        Active build <span class="font-medium text-primary">{@version}</span>
        (Build 42 · unstable), released {@date}.
      </p>
    </div>
    """
  end

  defp game_card(%{game: :loading} = assigns) do
    ~H"""
    <div class="card bg-base-200 p-4 text-base-content/60">
      <span class="loading loading-spinner loading-sm"></span> Reading game version…
    </div>
    """
  end

  defp game_card(%{game: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <div class="alert alert-warning">Couldn't read game version: {@reason}</div>
    """
  end

  attr :mods, :any, required: true

  defp mods_table(%{mods: :loading} = assigns) do
    ~H"""
    <div class="text-center text-base-content/60">
      <span class="loading loading-spinner loading-sm"></span> Loading mod list…
    </div>
    """
  end

  defp mods_table(%{mods: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <div class="alert alert-warning">Couldn't load mods: {@reason}</div>
    """
  end

  defp mods_table(%{mods: {:ok, mods}} = assigns) do
    assigns = assign(assigns, :mods_list, mods)

    ~H"""
    <div>
      <p class="text-sm text-base-content/60 mb-2">{length(@mods_list)} installed mods</p>
      <div class="overflow-x-auto">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th>Mod</th>
              <th>Installed</th>
              <th>Latest on Steam</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={mod <- @mods_list}>
              <td>
                <a href={Workshop.workshop_url(mod.id)} target="_blank" rel="noopener" class="link link-primary">
                  {mod.title}
                </a>
              </td>
              <td class="whitespace-nowrap">{fmt(mod.installed_at)}</td>
              <td class="whitespace-nowrap">{fmt(mod.latest_at)}</td>
              <td>
                <span :if={mod.up_to_date?} class="badge badge-success badge-sm">Up to date</span>
                <span :if={!mod.up_to_date?} class="badge badge-warning badge-sm">Update available</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
