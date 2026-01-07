import Config

# Firebase Admin SDK Configuration
# You can configure your Firebase credentials in one of two ways:

# Option 1: Path to service account JSON file
# config :firebase_admin,
#   project_id: "your-project-id",
#   credentials: "priv/service-account.json"

# Option 2: Inline credentials map
# config :firebase_admin,
#   project_id: "your-project-id",
#   credentials: %{
#     "type" => "service_account",
#     "project_id" => "your-project",
#     "private_key_id" => "key-id",
#     "private_key" => "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
#     "client_email" => "firebase-adminsdk@your-project.iam.gserviceaccount.com",
#     "client_id" => "1234567890",
#     "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
#     "token_uri" => "https://oauth2.googleapis.com/token",
#     "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
#     "client_x509_cert_url" => "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk@your-project.iam.gserviceaccount.com"
#   }

# Optional: Custom cache directory for DETS file
# config :firebase_admin,
#   cache_dir: "priv/cache"

# Environment-specific configuration
import_config "#{config_env()}.exs"
