defmodule ZombiWeb.Format do
  @moduledoc """
  Shared timestamp formatting for the web UI.

  All timestamps are stored in UTC. These helpers convert them to the viewer's
  local time zone (detected in the browser and pushed via LiveSocket connect
  params — see `assets/js/app.js`) and render them with `Calendar.strftime/2`.

  `on_mount/4` is attached to every LiveView (via `ZombiWeb.live_view/0`) and
  assigns `@timezone`, which the template helpers below read.
  """

  import Phoenix.LiveView, only: [get_connect_params: 1]
  import Phoenix.Component, only: [assign: 3]

  @fallback_zone "Etc/UTC"

  @doc "Assigns `@timezone` from the browser, falling back to UTC."
  def on_mount(:default, _params, _session, socket) do
    time_zone = (get_connect_params(socket) || %{})["timezone"] || @fallback_zone
    {:cont, assign(socket, :timezone, time_zone)}
  end

  @doc """
  Renders a UTC `DateTime` as "YYYY-MM-DD HH:MM <zone>" in the given time zone,
  e.g. `"2026-06-22 14:30 CEST"`. Returns `"—"` for `nil`.
  """
  def local_time(datetime, time_zone \\ @fallback_zone)
  def local_time(nil, _time_zone), do: "—"

  def local_time(%DateTime{} = dt, time_zone) do
    dt
    |> shift_zone(time_zone)
    |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  end

  # Browser-supplied zones are untrusted; an unknown name falls back to UTC
  # rather than raising. No atoms are created from the string.
  defp shift_zone(dt, time_zone) do
    case DateTime.shift_zone(dt, time_zone) do
      {:ok, shifted} -> shifted
      {:error, _reason} -> dt
    end
  end
end
