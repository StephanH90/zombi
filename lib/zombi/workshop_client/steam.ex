defmodule Zombi.WorkshopClient.Steam do
  @moduledoc """
  Real `Zombi.WorkshopClient` implementation: fetches the live Steam Workshop
  page with `Req` and scrapes the title and internal PZ mod IDs from the
  description.
  """

  @behaviour Zombi.WorkshopClient

  @impl true
  def fetch_mod_info(workshop_id) when is_binary(workshop_id) do
    case Req.get(Zombi.Workshop.workshop_url(workshop_id), receive_timeout: 15_000) do
      {:ok, %{status: 200, body: html}} ->
        {:ok, parse_mod_ids(html)}

      {:ok, %{status: status}} ->
        {:error, "Steam returned status #{status}"}

      {:error, reason} ->
        {:error, "request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Pure scraper: pulls the page title and the internal `Mod ID:` values out of a
  Steam Workshop page's HTML.

  Mod IDs are deduped while preserving first-seen order. The title is taken from
  the `workshopItemTitle` div, falling back to the `<title>` tag (stripping the
  `Steam Workshop::` prefix), and finally to an empty string. Missing mod IDs
  yield `mod_ids: []` rather than an error.
  """
  def parse_mod_ids(html) when is_binary(html) do
    %{title: extract_title(html), mod_ids: extract_mod_ids(html)}
  end

  defp extract_mod_ids(html) do
    ~r/Mod ID:\s*([A-Za-z0-9_\-\.]+)/
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [id] -> id end)
    |> Enum.uniq()
  end

  defp extract_title(html) do
    cond do
      title = match_capture(~r/<div class="workshopItemTitle">(.*?)<\/div>/s, html) ->
        String.trim(title)

      title = match_capture(~r/<title>(.*?)<\/title>/s, html) ->
        title
        |> String.replace_prefix("Steam Workshop::", "")
        |> String.trim()

      true ->
        ""
    end
  end

  defp match_capture(regex, html) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [value] -> value
      nil -> nil
    end
  end
end
