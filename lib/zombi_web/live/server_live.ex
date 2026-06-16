defmodule ZombiWeb.ServerLive do
  use ZombiWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :restarting?, false)}
  end

  def handle_event("restart", _params, socket) do
    {:noreply,
     socket
     |> assign(:restarting?, true)
     |> start_async(:restart, &Zombi.GameServer.restart/0)}
  end

  def handle_async(:restart, {:ok, {:ok, _output}}, socket) do
    {:noreply,
     socket
     |> assign(:restarting?, false)
     |> put_flash(:info, "Server restarted.")}
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center gap-6 py-10">
        <h1 class="text-2xl font-semibold">Project Zomboid Server</h1>
        <p class="text-base-content/70 text-center">
          Use this if the server is acting up. Restarting takes a moment.
        </p>
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
end
