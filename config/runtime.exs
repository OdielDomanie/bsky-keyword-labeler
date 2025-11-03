import Config

# Read secret files, latter takes priority, comma seperated, backslash escaped
secret_files =
  System.get_env("SECRET_FILES", "/run/secrets/bsky_politics_labeler_secret,secret")
  |> String.split(~r/(?<!\\),/)
  |> Enum.map(&String.replace(&1, "\\\\", "\\"))

key_vals =
  for secret_file <- secret_files,
      {:ok, content} <- [File.read(secret_file)],
      IO.puts("Loaded secrets from #{secret_file}"),
      line <- String.split(content, "\n"),
      not String.starts_with?(line, "#"),
      line != "" do
    String.split(line, "=", parts: 2) |> List.to_tuple()
  end

# Last file takes priority
secret_map = Map.new(key_vals)

get = fn key -> System.get_env(key, secret_map[key]) end

config :bsky_politics_labeler,
  labeler_did: get.("LABELER_DID"),
  labeler_password: get.("LABELER_PASSWORD"),
  admin_dashboard_password: get.("DASHBOARD_PASSWORD"),
  start_websocket: System.get_env("START_WEBSOCKET") == "true",
  simulate_emit_event: System.get_env("LABELER_SIMULATE") == "true",
  min_likes:
    System.get_env("MIN_LIKES", "50")
    |> String.to_integer(),
  regex_file: System.get_env("REGEX_FILE", "patterns.txt")

config :bsky_politics_labeler, BskyPoliticsLabeler.Repo,
  log: false,
  database: "bsky_politics_labeler_repo",
  username: "postgres",
  password: get.("POSTGRES_PASSWORD") || "dev_postgres_pw",
  hostname: get.("POSTGRES_HOST") || "localhost",
  port: get.("POSTGRES_PORT") || "5432"

config :bsky_politics_labeler, BskyPoliticsLabeler.WebEndpoint,
  secret_key_base: get.("PHOENIX_SECRET_KEY_BASE")
