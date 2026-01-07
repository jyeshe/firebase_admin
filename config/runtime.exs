import Config

# Runtime configuration for production deployments
# This file is executed when the application starts

if config_env() == :prod do
  # Read credentials from environment variables
  credentials_path = System.get_env("FIREBASE_CREDENTIALS_PATH")
  credentials_json = System.get_env("FIREBASE_CREDENTIALS_JSON")
  project_id = System.get_env("FIREBASE_PROJECT_ID")

  credentials =
    cond do
      credentials_json != nil ->
        Jason.decode!(credentials_json)

      credentials_path != nil ->
        credentials_path

      true ->
        raise "Either FIREBASE_CREDENTIALS_PATH or FIREBASE_CREDENTIALS_JSON must be set in production"
    end

  config :firebase_admin,
    project_id: project_id || raise("FIREBASE_PROJECT_ID must be set in production"),
    credentials: credentials
end
