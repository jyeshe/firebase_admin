import Config

# Integration test configuration for Firebase
# This configuration uses real Firebase services

# Firebase project configuration
config :firebase_admin,
  fcm_sender_id: "",
  cache_dir: "test/integration_cache",
  use_real_firebase: true,
  max_fetch_retries: 2

# Configure logger for integration tests
config :logger, level: :info

# Configure Goth for OAuth with real credentials (loaded at runtime)
# config :goth, json: File.read!("firebase-sa-test.json")
