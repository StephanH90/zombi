defmodule Zombi.LogCollector do
  @moduledoc """
  Follows `docker logs -f` for the Project Zomboid container via a Port,
  keeps the last 500 lines in memory, and broadcasts each new line over
  PubSub. A single collector serves all viewers. If the log stream ends (e.g.
  the container restarts) it reopens automatically.
  """
  use GenServer
  require Logger

  @topic "zomboid_logs"
  @max 500

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "PubSub topic that receives `{:log_line, %{id, text}}` messages."
  def topic, do: @topic

  @doc "Current buffered lines, oldest first."
  def buffer, do: GenServer.call(__MODULE__, :buffer)

  @impl true
  def init(_) do
    {:ok, open(%{port: nil, next_id: 0, partial: "", buffer: []})}
  end

  defp open(state) do
    container = Application.fetch_env!(:zombi, :pz_container)

    case System.find_executable("docker") do
      nil ->
        state

      docker ->
        port =
          Port.open(
            {:spawn_executable, docker},
            [
              :binary,
              :exit_status,
              {:line, 65_536},
              args: ["logs", "-f", "--tail", "#{@max}", container]
            ]
          )

        %{state | port: port, partial: ""}
    end
  end

  @impl true
  def handle_call(:buffer, _from, state), do: {:reply, Enum.reverse(state.buffer), state}

  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | partial: state.partial <> chunk}}
  end

  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    {:noreply, push_line(state, state.partial <> chunk)}
  end

  def handle_info({port, {:exit_status, _status}}, %{port: port} = state) do
    Process.send_after(self(), :reopen, 2_000)
    {:noreply, %{state | port: nil}}
  end

  def handle_info(:reopen, state), do: {:noreply, open(state)}
  def handle_info(_msg, state), do: {:noreply, state}

  defp push_line(state, text) do
    entry = %{id: state.next_id, text: text}
    Phoenix.PubSub.broadcast(Zombi.PubSub, @topic, {:log_line, entry})

    %{
      state
      | next_id: state.next_id + 1,
        partial: "",
        buffer: Enum.take([entry | state.buffer], @max)
    }
  end
end
