defmodule ZombiWeb.ModsLive do
  use ZombiWeb, :live_view

  alias Zombi.Workshop

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(mods: :loading, game: :loading, active: :loading)
      |> assign(staged_workshop_ids: [], staged_mod_ids: [], dirty?: false)
      |> assign(pending_confirm: nil, activating?: false)
      |> assign(add_form: add_form())

    socket = if connected?(socket), do: load(socket), else: socket
    {:ok, socket}
  end

  # --- existing handlers (kept) ---

  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> assign(mods: :loading, game: :loading, active: :loading)
     |> load()}
  end

  # --- editor: removals (operate on the staged working set) ---

  def handle_event("remove_workshop", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:staged_workshop_ids, List.delete(socket.assigns.staged_workshop_ids, id))
     |> assign(:dirty?, true)}
  end

  def handle_event("remove_mod", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:staged_mod_ids, List.delete(socket.assigns.staged_mod_ids, id))
     |> assign(:dirty?, true)}
  end

  # --- editor: add by link ---

  def handle_event("lookup", %{"add" => %{"link" => link}}, socket) do
    link = String.trim(link)

    if link == "" do
      {:noreply, put_flash(socket, :error, "Enter a Steam Workshop link or id first.")}
    else
      {:noreply, start_async(socket, :resolve, fn -> Zombi.Mods.resolve_link(link) end)}
    end
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, socket |> assign(:pending_confirm, nil) |> assign(:add_form, add_form())}
  end

  def handle_event("confirm_add", params, socket) do
    %{workshop_id: workshop_id} = socket.assigns.pending_confirm
    confirm = Map.get(params, "confirm", %{})

    chosen =
      case Map.get(confirm, "mod_ids") do
        ids when is_list(ids) -> Enum.reject(ids, &(&1 in ["", nil]))
        _ -> []
      end

    manual =
      confirm
      |> Map.get("manual_mod_id", "")
      |> String.trim()

    mod_ids = Enum.reject([manual | chosen], &(&1 == ""))

    if mod_ids == [] do
      {:noreply, put_flash(socket, :error, "Pick or enter at least one mod id.")}
    else
      {:noreply,
       socket
       |> assign(
         :staged_workshop_ids,
         Enum.uniq(socket.assigns.staged_workshop_ids ++ [workshop_id])
       )
       |> assign(:staged_mod_ids, Enum.uniq(socket.assigns.staged_mod_ids ++ mod_ids))
       |> assign(:dirty?, true)
       |> assign(:pending_confirm, nil)
       |> assign(:add_form, add_form())}
    end
  end

  # --- editor: activate ---

  def handle_event("activate", _params, socket) do
    workshop_ids = socket.assigns.staged_workshop_ids
    mod_ids = socket.assigns.staged_mod_ids

    {:noreply,
     socket
     |> assign(:activating?, true)
     |> start_async(:activate, fn -> Zombi.Mods.activate_mods(workshop_ids, mod_ids) end)}
  end

  # --- async results ---

  def handle_async(:mods, {:ok, result}, socket), do: {:noreply, assign(socket, :mods, result)}

  def handle_async(:mods, {:exit, r}, socket),
    do: {:noreply, assign(socket, :mods, {:error, inspect(r)})}

  def handle_async(:game, {:ok, result}, socket), do: {:noreply, assign(socket, :game, result)}

  def handle_async(:game, {:exit, r}, socket),
    do: {:noreply, assign(socket, :game, {:error, inspect(r)})}

  def handle_async(:active, {:ok, %{workshop_ids: workshop_ids, mod_ids: mod_ids}}, socket) do
    {:noreply,
     socket
     |> assign(:active, :ok)
     |> assign(:staged_workshop_ids, workshop_ids)
     |> assign(:staged_mod_ids, mod_ids)
     |> assign(:dirty?, false)}
  end

  def handle_async(:active, {:exit, r}, socket) do
    {:noreply, socket |> assign(:active, {:error, inspect(r)})}
  end

  def handle_async(:resolve, {:ok, {:ok, %{} = info}}, socket) do
    {:noreply, assign(socket, :pending_confirm, info)}
  end

  def handle_async(:resolve, {:ok, {:error, reason}}, socket) do
    {:noreply, put_flash(socket, :error, "Lookup failed: #{format_error(reason)}")}
  end

  def handle_async(:resolve, {:exit, r}, socket) do
    {:noreply, put_flash(socket, :error, "Lookup crashed: #{inspect(r)}")}
  end

  def handle_async(
        :activate,
        {:ok, {:ok, %{workshop_ids: workshop_ids, mod_ids: mod_ids}}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:activating?, false)
     |> assign(:staged_workshop_ids, workshop_ids)
     |> assign(:staged_mod_ids, mod_ids)
     |> assign(:dirty?, false)
     |> put_flash(:info, "Mods activated, server restarting.")
     |> assign(mods: :loading, active: :loading)
     |> reload_after_activate()}
  end

  def handle_async(:activate, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:activating?, false)
     |> put_flash(:error, "Activation failed: #{format_error(reason)}")}
  end

  def handle_async(:activate, {:exit, r}, socket) do
    {:noreply,
     socket
     |> assign(:activating?, false)
     |> put_flash(:error, "Activation crashed: #{inspect(r)}")}
  end

  # --- loaders ---

  defp load(socket) do
    socket
    |> start_async(:mods, &Workshop.all_mods/0)
    |> start_async(:game, &Zombi.GameServer.version/0)
    |> start_async(:active, &Zombi.Mods.current_mods!/0)
  end

  defp reload_after_activate(socket) do
    socket
    |> start_async(:mods, &Workshop.all_mods/0)
    |> start_async(:active, &Zombi.Mods.current_mods!/0)
  end

  defp add_form, do: to_form(%{"link" => ""}, as: :add)

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  # --- render ---

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

        <.editor
          active={@active}
          staged_workshop_ids={@staged_workshop_ids}
          staged_mod_ids={@staged_mod_ids}
          dirty?={@dirty?}
          activating?={@activating?}
          pending_confirm={@pending_confirm}
          add_form={@add_form}
        />

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

  # --- editor card ---

  attr :active, :any, required: true
  attr :staged_workshop_ids, :list, required: true
  attr :staged_mod_ids, :list, required: true
  attr :dirty?, :boolean, required: true
  attr :activating?, :boolean, required: true
  attr :pending_confirm, :any, required: true
  attr :add_form, :any, required: true

  defp editor(%{active: :loading} = assigns) do
    ~H"""
    <div class="card bg-base-200 p-4 text-base-content/60">
      <span class="loading loading-spinner loading-sm"></span> Loading active mod list…
    </div>
    """
  end

  defp editor(%{active: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <div class="alert alert-warning">Couldn't load active mod list: {@reason}</div>
    """
  end

  defp editor(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4 flex flex-col gap-6">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold">Edit mod list</h2>
        <div :if={@dirty?} class="badge badge-warning">Unsaved changes · restart required</div>
      </div>

      <.add_panel add_form={@add_form} pending_confirm={@pending_confirm} />

      <div class="grid gap-6 md:grid-cols-2">
        <div>
          <h3 class="font-medium mb-2">Workshop items</h3>
          <p :if={@staged_workshop_ids == []} class="text-sm text-base-content/60">None.</p>
          <ul class="divide-y divide-base-300 rounded-box border border-base-300">
            <li
              :for={id <- @staged_workshop_ids}
              class="flex items-center justify-between gap-2 p-2"
            >
              <a
                href={Workshop.workshop_url(id)}
                target="_blank"
                rel="noopener"
                class="link link-primary font-mono text-sm"
              >
                {id}
              </a>
              <button
                class="btn btn-xs btn-ghost"
                phx-click="remove_workshop"
                phx-value-id={id}
              >
                Remove
              </button>
            </li>
          </ul>
        </div>

        <div>
          <h3 class="font-medium mb-2">Mod IDs (load order)</h3>
          <p :if={@staged_mod_ids == []} class="text-sm text-base-content/60">None.</p>
          <ul class="divide-y divide-base-300 rounded-box border border-base-300">
            <li
              :for={id <- @staged_mod_ids}
              class="flex items-center justify-between gap-2 p-2"
            >
              <span class="font-mono text-sm">{id}</span>
              <button class="btn btn-xs btn-ghost" phx-click="remove_mod" phx-value-id={id}>
                Remove
              </button>
            </li>
          </ul>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <button
          id="activate-button"
          class="btn btn-primary"
          phx-click="activate"
          disabled={@activating?}
        >
          <%= if @activating? do %>
            <span class="loading loading-spinner loading-sm"></span> Activating &amp; restarting…
          <% else %>
            Activate
          <% end %>
        </button>
        <span :if={@dirty? and not @activating?} class="text-sm text-base-content/60">
          Activating writes the config and restarts the server.
        </span>
      </div>
    </div>
    """
  end

  attr :add_form, :any, required: true
  attr :pending_confirm, :any, required: true

  defp add_panel(%{pending_confirm: nil} = assigns) do
    ~H"""
    <.form id="add-mod-form" for={@add_form} phx-submit="lookup" class="flex items-end gap-2">
      <div class="flex-1">
        <.input
          field={@add_form[:link]}
          type="text"
          label="Add a mod by Steam Workshop link"
          placeholder="https://steamcommunity.com/sharedfiles/filedetails/?id=…"
        />
      </div>
      <button type="submit" class="btn btn-secondary">Look up</button>
    </.form>
    """
  end

  defp add_panel(assigns) do
    %{workshop_id: workshop_id, title: title, mod_ids: mod_ids} = assigns.pending_confirm
    assigns = assign(assigns, workshop_id: workshop_id, title: title, mod_ids: mod_ids)

    ~H"""
    <div id="confirm-add" class="rounded-box border border-primary/50 bg-base-100 p-4">
      <h3 class="font-medium mb-1">{@title}</h3>
      <p class="text-sm text-base-content/60 mb-3 font-mono">Workshop id: {@workshop_id}</p>

      <form id="confirm-add-form" phx-submit="confirm_add" class="flex flex-col gap-3">
        <%= if @mod_ids == [] do %>
          <p class="text-sm text-base-content/70">
            No mod ids were found on the page. Enter one manually (PZ needs at least one):
          </p>
          <input
            type="text"
            name="confirm[manual_mod_id]"
            class="input input-bordered w-full max-w-xs"
            placeholder="ModID"
          />
        <% else %>
          <p class="text-sm text-base-content/70">Choose which mod ids to add:</p>
          <div class="flex flex-col gap-1">
            <label :for={id <- @mod_ids} class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="confirm[mod_ids][]"
                value={id}
                checked
                class="checkbox checkbox-sm"
              />
              <span class="font-mono text-sm">{id}</span>
            </label>
          </div>
        <% end %>

        <div class="flex gap-2">
          <button type="submit" class="btn btn-sm btn-primary">Add to list</button>
          <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_add">Cancel</button>
        </div>
      </form>
    </div>
    """
  end

  # --- steam-update table (kept) ---

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
                <a
                  href={Workshop.workshop_url(mod.id)}
                  target="_blank"
                  rel="noopener"
                  class="link link-primary"
                >
                  {mod.title}
                </a>
              </td>
              <td class="whitespace-nowrap">{local_time(mod.installed_at, @timezone)}</td>
              <td class="whitespace-nowrap">{local_time(mod.latest_at, @timezone)}</td>
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
end
