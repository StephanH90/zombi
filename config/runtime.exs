import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/zombi start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :zombi, ZombiWeb.Endpoint, server: true
end

config :zombi, ZombiWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Basic auth credentials and the Project Zomboid docker compose directory.
# Set AUTH_PASSWORD and PZ_COMPOSE_DIR in the gameserver environment.
config :zombi, :basic_auth,
  username: System.get_env("AUTH_USERNAME", "admin"),
  password: System.get_env("AUTH_PASSWORD", "changeme")

config :zombi, :compose_dir, System.get_env("PZ_COMPOSE_DIR", ".")
config :zombi, :pz_server_name, System.get_env("PZ_SERVER_NAME", "servertest")
config :zombi, :pz_container, System.get_env("PZ_CONTAINER", "projectzomboid")

# Where one-click backups are written. Defaults to <compose_dir>/backups.
# Only used by the real Zombi.Backup.Tar impl; dev/test set this in their config.
config :zombi,
       :backups_dir,
       System.get_env("PZ_BACKUPS_DIR") ||
         Path.join(System.get_env("PZ_COMPOSE_DIR", "."), "backups")

config :zombi, :rcon,
  host: System.get_env("RCON_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("RCON_PORT", "27015")),
  password: System.get_env("RCON_PASSWORD", "")

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/zombi/zombi.db
      """

  config :zombi, Zombi.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :zombi, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Websocket origin allowlist. Defaults to the configured host; set
  # PHX_ALLOWED_ORIGINS to a comma-separated list to allow several (e.g. both a
  # bare IP and a domain).
  check_origin =
    case System.get_env("PHX_ALLOWED_ORIGINS") do
      nil -> ["//#{host}"]
      csv -> String.split(csv, ",", trim: true)
    end

  config :zombi, ZombiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: check_origin,
    http: [
      # Bind to IPv4 loopback only; the public TLS endpoint is Caddy, which
      # reverse-proxies to 127.0.0.1:4000.
      ip: {127, 0, 0, 1}
    ],
    secret_key_base: secret_key_base

  # Native HTTPS listener. Enabled when SSL_CERT_PATH is set (e.g. a
  # self-signed cert). Friends will see a browser warning for self-signed
  # certs but the connection is encrypted.
  if cert_path = System.get_env("SSL_CERT_PATH") do
    config :zombi, ZombiWeb.Endpoint,
      https: [
        port: String.to_integer(System.get_env("SSL_PORT", "443")),
        cipher_suite: :strong,
        certfile: cert_path,
        keyfile: System.fetch_env!("SSL_KEY_PATH"),
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      ]
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :zombi, ZombiWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :zombi, ZombiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :zombi, Zombi.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
