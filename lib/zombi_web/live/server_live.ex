defmodule ZombiWeb.ServerLive do
  use ZombiWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:restarting?, false)
     |> assign(:mods, :loading)
     |> check_mods()}
  end

  def handle_event("restart", _params, socket) do
    {:noreply,
     socket
     |> assign(:restarting?, true)
     |> start_async(:restart, &Zombi.GameServer.restart/0)}
  end

  def handle_event("check_mods", _params, socket) do
    {:noreply, socket |> assign(:mods, :loading) |> check_mods()}
  end

  def handle_async(:restart, {:ok, {:ok, _output}}, socket) do
    {:noreply,
     socket
     |> assign(:restarting?, false)
     |> put_flash(:info, "Server restarted.")
     |> assign(:mods, :loading)
     |> check_mods()}
  end

  def handle_async(:restart, {:ok, {:error, message}}, socket) do
    {:noreply,
     socket
     |> assign(:restarting?, false)
     |> put_flash(:error, "Restart failed: #{message}")}
  end

  def handle_async(:restart, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:restarting?, false)
     |> put_flash(:error, "Restart crashed: #{inspect(reason)}")}
  end

  def handle_async(:check_mods, {:ok, {:ok, updates}}, socket) do
    {:noreply, assign(socket, :mods, {:ok, updates})}
  end

  def handle_async(:check_mods, {:ok, {:error, message}}, socket) do
    {:noreply, assign(socket, :mods, {:error, message})}
  end

  def handle_async(:check_mods, {:exit, reason}, socket) do
    {:noreply, assign(socket, :mods, {:error, "check crashed: #{inspect(reason)}"})}
  end

  defp check_mods(socket) do
    start_async(socket, :check_mods, &Zombi.Workshop.pending_updates/0)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center gap-6 py-10">
        <h1 class="text-2xl font-semibold">Project Zomboid Server</h1>
        <p class="text-base-content/70 text-center">
          Use this if the server is acting up, or when mods need updating. Restarting
          takes a moment and pulls the latest workshop mod versions.
        </p>

        <.mod_status mods={@mods} />

        <button
          id="restart-button"
          class="btn btn-primary btn-lg"
          phx-click="restart"
          disabled={@restarting?}
        >
          <%= if @restarting? do %>
            <span class="loading loading-spinner"></span> Restarting…
          <% else %>
            Restart Server
          <% end %>
        </button>
      </div>
    </Layouts.app>
    """
  end

  attr :mods, :any, required: true

  defp mod_status(%{mods: :loading} = assigns) do
    ~H"""
    <div class="w-full text-center text-base-content/60" id="mod-status">
      <span class="loading loading-spinner loading-sm"></span> Checking mods for updates…
    </div>
    """
  end

  defp mod_status(%{mods: {:error, _}} = assigns) do
    ~H"""
    <div class="alert alert-warning w-full" id="mod-status">
      <span>Couldn't check mod updates: {elem(@mods, 1)}</span>
      <button class="btn btn-sm" phx-click="check_mods">Retry</button>
    </div>
    """
  end

  defp mod_status(%{mods: {:ok, []}} = assigns) do
    ~H"""
    <div class="alert alert-success w-full" id="mod-status">
      <span>All mods are up to date.</span>
      <button class="btn btn-sm" phx-click="check_mods">Check now</button>
    </div>
    """
  end

  defp mod_status(%{mods: {:ok, _updates}} = assigns) do
    ~H"""
    <div class="w-full space-y-2" id="mod-status">
      <div class="flex items-center justify-between">
        <span class="font-medium text-warning">
          {length(elem(@mods, 1))} mod(s) need updating — restart to apply
        </span>
        <button class="btn btn-sm" phx-click="check_mods">Check now</button>
      </div>
      <ul class="divide-y divide-base-300 rounded-box border border-base-300">
        <li :for={mod <- elem(@mods, 1)} class="flex flex-col gap-1 p-3">
          <a
            href={"https://steamcommunity.com/sharedfiles/filedetails/?id=#{mod.id}"}
            target="_blank"
            rel="noopener"
            class="link link-primary font-medium"
          >
            {mod.title}
          </a>
          <span class="text-sm text-base-content/60">
            Updated {Calendar.strftime(mod.updated_at, "%Y-%m-%d %H:%M UTC")} ({relative_time(
              mod.behind_seconds
            )} behind)
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp relative_time(seconds) when seconds >= 86_400, do: "#{div(seconds, 86_400)}d"
  defp relative_time(seconds) when seconds >= 3_600, do: "#{div(seconds, 3_600)}h"
  defp relative_time(seconds) when seconds >= 60, do: "#{div(seconds, 60)}m"
  defp relative_time(seconds), do: "#{seconds}s"
end
