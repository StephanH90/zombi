defmodule ZombiWeb.LogsLive do
  use ZombiWeb, :live_view

  def mount(_params, _session, socket) do
    lines =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Zombi.PubSub, Zombi.LogCollector.topic())
        Zombi.LogCollector.buffer()
      else
        []
      end

    {:ok, stream(socket, :logs, lines, limit: -500)}
  end

  def handle_info({:log_line, entry}, socket) do
    {:noreply, stream_insert(socket, :logs, entry, limit: -500)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <Layouts.tabs active={:logs} />
      <div class="flex flex-col gap-4 py-10">
        <h1 class="text-2xl font-semibold">Server Logs</h1>
        <p class="text-sm text-base-content/60">
          Live <code>docker logs</code> for the Zomboid server — last 500 lines.
        </p>
        <div
          id="log-box"
          phx-update="stream"
          phx-hook=".AutoScroll"
          class="bg-base-300 rounded-box p-3 h-[65vh] overflow-y-auto font-mono text-xs leading-relaxed whitespace-pre-wrap break-words"
        >
          <div :for={{dom_id, line} <- @streams.logs} id={dom_id}>{line.text}</div>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoScroll">
        export default {
          mounted() { this.el.scrollTop = this.el.scrollHeight },
          beforeUpdate() {
            this.atBottom =
              this.el.scrollHeight - this.el.clientHeight - this.el.scrollTop < 60
          },
          updated() { if (this.atBottom) this.el.scrollTop = this.el.scrollHeight },
        }
      </script>
    </Layouts.app>
    """
  end
end
