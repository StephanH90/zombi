defmodule Zombi.Rcon do
  @moduledoc """
  Minimal Source RCON client (the protocol Project Zomboid's RCON uses).

  Connects over TCP, authenticates with the password, runs a single command,
  and returns the response body. Handles responses split across multiple
  packets (large replies) by draining until the socket goes idle.
  """

  @auth 3
  @exec 2
  @auth_response 2

  @doc """
  Runs `command` against the configured RCON server and returns `{:ok, body}`
  or `{:error, reason}`.
  """
  def command(command, opts \\ []) do
    cfg = Application.get_env(:zombi, :rcon, [])
    host = opts |> Keyword.get(:host, cfg[:host]) |> to_charlist()
    port = Keyword.get(opts, :port, cfg[:port])
    password = Keyword.get(opts, :password, cfg[:password])
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, sock} <-
           :gen_tcp.connect(host, port, [:binary, active: false, packet: :raw], timeout),
         {:auth, :ok} <- {:auth, authenticate(sock, password, timeout)},
         {:ok, body} <- exec(sock, command, timeout) do
      :gen_tcp.close(sock)
      {:ok, body}
    else
      {:auth, {:error, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- protocol ---

  defp encode(id, type, body) do
    payload = <<id::little-signed-32, type::little-32>> <> body <> <<0, 0>>
    <<byte_size(payload)::little-32>> <> payload
  end

  defp recv_packet(sock, timeout) do
    with {:ok, <<len::little-32>>} <- :gen_tcp.recv(sock, 4, timeout),
         {:ok, <<id::little-signed-32, type::little-32, rest::binary>>} <-
           :gen_tcp.recv(sock, len, timeout) do
      body = binary_part(rest, 0, max(byte_size(rest) - 2, 0))
      {:ok, id, type, body}
    end
  end

  defp authenticate(sock, password, timeout) do
    case :gen_tcp.send(sock, encode(1, @auth, password)) do
      :ok -> read_auth(sock, timeout)
      error -> error
    end
  end

  # The server may send an empty RESPONSE_VALUE before the AUTH_RESPONSE.
  # id == -1 in the auth response means the password was rejected.
  defp read_auth(sock, timeout) do
    case recv_packet(sock, timeout) do
      {:ok, -1, _type, _body} -> {:error, :auth_failed}
      {:ok, _id, @auth_response, _body} -> :ok
      {:ok, _id, _type, _body} -> read_auth(sock, timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  defp exec(sock, command, timeout) do
    case :gen_tcp.send(sock, encode(2, @exec, command)) do
      :ok ->
        case recv_packet(sock, timeout) do
          {:ok, _id, _type, body} -> {:ok, drain(sock, body)}
          {:error, reason} -> {:error, reason}
        end

      error ->
        error
    end
  end

  # Keep reading follow-up packets with a short timeout; stop once the socket
  # is idle (the full response has arrived).
  defp drain(sock, acc) do
    case recv_packet(sock, 150) do
      {:ok, _id, _type, body} -> drain(sock, acc <> body)
      {:error, _} -> acc
    end
  end
end
