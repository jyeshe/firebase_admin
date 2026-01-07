# Firebase Admin SDK for Elixir

A Firebase Admin SDK implementation for Elixir, providing a subset of Firebase functionality with a focus on:

- **ID Token Verification** - Verify Firebase Authentication ID tokens using Joken
- **Refresh Token Revocation** - Revoke user refresh tokens to sign them out
- **Firebase Cloud Messaging (FCM)** - Send push notifications to devices
- **FCM Multicast** - Efficiently send messages to multiple devices
- **Cloud Storage** - Upload, download, and manage files in Firebase Storage

This library is heavily inspired by the official Firebase Admin Go SDK but tailored for Elixir's strengths in concurrency and fault tolerance.

## Installation

Add `firebase_admin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:firebase_admin, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Configuration

### Option 1: Service Account JSON File

Download your Firebase service account key from the Firebase Console and configure the path:

```elixir
# config/config.exs
config :firebase_admin,
  project_id: "your-project-id",
  credentials: "priv/service-account.json"
```

### Option 2: Inline Credentials

Alternatively, provide credentials directly (useful for environment-based configuration):

```elixir
config :firebase_admin,
  project_id: "your-project-id",
  credentials: %{
    "type" => "service_account",
    "project_id" => "your-project",
    "private_key_id" => "...",
    "private_key" => "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
    "client_email" => "firebase-adminsdk@your-project.iam.gserviceaccount.com",
    "client_id" => "...",
    "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url" => "..."
  }
```

### Production Configuration

For production, use runtime configuration with environment variables:

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :firebase_admin,
    project_id: System.get_env("FIREBASE_PROJECT_ID"),
    credentials: System.get_env("FIREBASE_CREDENTIALS_PATH")
end
```

## Usage

### ID Token Verification

Verify Firebase ID tokens to authenticate users:

```elixir
case FirebaseAdmin.verify_token(id_token) do
  {:ok, claims} ->
    user_id = claims["sub"]
    email = claims["email"]
    IO.puts("Authenticated user: #{user_id} (#{email})")
    
  {:error, :token_expired} ->
    IO.puts("Token has expired")
    
  {:error, reason} ->
    IO.puts("Verification failed: #{inspect(reason)}")
end
```

The token verifier automatically:
- Fetches Google's public keys
- Caches them using `:dets` for persistence
- Refreshes keys every hour
- Validates all required claims (issuer, audience, expiration, etc.)

### Refresh Token Revocation

Sign out a user from all devices:

```elixir
case FirebaseAdmin.revoke_refresh_tokens(user_id) do
  :ok ->
    IO.puts("User signed out from all devices")
    
  {:error, reason} ->
    IO.puts("Failed to revoke tokens: #{inspect(reason)}")
end
```

### Firebase Cloud Messaging

#### Send to a Single Device

```elixir
message = %{
  token: "device_fcm_token",
  notification: %{
    title: "Hello from Elixir!",
    body: "This is a push notification"
  },
  data: %{
    "custom_key" => "custom_value",
    "action" => "open_chat"
  }
}

case FirebaseAdmin.send_message(message) do
  {:ok, message_id} ->
    IO.puts("Message sent: #{message_id}")
    
  {:error, reason} ->
    IO.puts("Failed to send: #{inspect(reason)}")
end
```

#### Platform-Specific Options

```elixir
message = %{
  token: "device_token",
  notification: %{
    title: "New Message",
    body: "You have a new message"
  },
  # Android-specific
  android: %{
    priority: "high",
    notification: %{
      sound: "default",
      color: "#ff0000",
      icon: "notification_icon"
    }
  },
  # iOS-specific
  apns: %{
    payload: %{
      aps: %{
        sound: "default",
        badge: 1,
        alert: %{
          title: "New Message",
          body: "You have a new message"
        }
      }
    }
  },
  # Web-specific
  webpush: %{
    notification: %{
      icon: "https://example.com/icon.png",
      badge: "https://example.com/badge.png"
    }
  }
}

FirebaseAdmin.send_message(message)
```

#### Multicast (Multiple Devices)

Send the same message to multiple devices efficiently with concurrent requests:

```elixir
message = %{
  tokens: [
    "token1",
    "token2",
    "token3",
    # ... up to 500 tokens
  ],
  notification: %{
    title: "Broadcast Message",
    body: "This goes to all devices"
  }
}

case FirebaseAdmin.send_multicast(message) do
  {:ok, %{success_count: success, failure_count: failures, responses: responses}} ->
    IO.puts("Sent to #{success} devices, #{failures} failures")
    
    # Check individual results
    Enum.each(Enum.with_index(responses), fn {result, index} ->
      case result do
        {:ok, message_id} ->
          IO.puts("Token #{index}: Success - #{message_id}")
        {:error, reason} ->
          IO.puts("Token #{index}: Failed - #{reason}")
      end
    end)
    
  {:error, reason} ->
    IO.puts("Multicast failed: #{inspect(reason)}")
end
```

The multicast feature:
- Sends up to 10 concurrent requests by default
- Automatically handles rate limiting
- Returns individual results for each token
- Efficiently processes large batches

## Architecture

### Token Verification with DETS Caching

The token verifier uses a GenServer that:
1. Fetches Google's public keys on startup
2. Caches them in a DETS table for persistence across restarts
3. Automatically refreshes keys every hour
4. Falls back to cached keys if refresh fails
5. Uses Joken for JWT verification with RS256 algorithm

### FCM Multicast Optimization

The multicast implementation uses Elixir's `Task.async_stream` to:
- Send multiple requests concurrently (configurable concurrency limit)
- Respect rate limits
- Collect individual results for each token
- Handle failures gracefully without blocking other sends

### Error Handling

All functions return tagged tuples for pattern matching:
- `{:ok, result}` - Success
- `{:error, reason}` - Failure with descriptive reason

Common error reasons:
- `:no_credentials` - Firebase credentials not configured
- `:token_expired` - ID token has expired
- `:invalid_token` - Malformed or invalid token
- `:file_not_found` - Storage file doesn't exist
- FCM errors: `"InvalidRegistration"`, `"NotRegistered"`, etc.

## Testing

Run tests with:

```bash
mix test
```

The test suite includes:
- Token verification tests
- DETS caching tests
- Mocked HTTP requests using Bypass
- Integration test examples

## Design Decisions

### Why Joken over JOSE?

While JOSE is a comprehensive JWT library, Joken provides:
- Simpler API for token verification
- Built-in claim validation
- Better error messages
- More ergonomic configuration

### Why DETS for Caching?

DETS (Disk-based term storage) provides:
- Persistence across application restarts
- No external dependencies
- Built into Erlang/OTP
- Simple key-value storage suitable for this use case

Alternative caching strategies (ETS, Redis, etc.) could be implemented if needed.

### Why Req over HTTPoison/Tesla?

Req offers:
- Modern, high-level API
- Built-in JSON handling
- Automatic retries
- Better documentation
- Active maintenance

## Comparison with Go SDK

This library implements a focused subset of the Firebase Admin Go SDK:

| Feature | Go SDK | This Library | Status |
|---------|--------|--------------|--------|
| Auth - ID Token Verification | ✓ | ✓ | Complete |
| Auth - Token Revocation | ✓ | ✓ | Complete |
| Auth - User Management | ✓ | ✗ | Not implemented |
| FCM - Send Message | ✓ | ✓ | Complete |
| FCM - Multicast | ✓ | ✓ | Complete |
| FCM - Topic Management | ✓ | ✗ | Not implemented |
| Cloud Storage | ✓ | ✓ | Complete |
| Firestore | ✓ | ✗ | Not implemented |
| Realtime Database | ✓ | ✗ | Not implemented |

## Performance Considerations

- **Token Verification**: First verification requires fetching public keys (~100-200ms). Subsequent verifications are fast (~1-2ms) using cached keys.
- **FCM Multicast**: Sending to 100 devices takes approximately 1-3 seconds with 10 concurrent requests.
- **Storage Operations**: Performance depends on file size and network conditions. Large files (>10MB) should be streamed.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

Areas for improvement:
- Additional Firebase services (Firestore, Realtime Database)
- User management APIs
- FCM topic subscription management
- Enhanced error handling and retry logic
- Performance optimizations
- More comprehensive test coverage

## License

MIT License - see LICENSE file for details.

## Acknowledgments

This library is inspired by the official [Firebase Admin Go SDK](https://github.com/firebase/firebase-admin-go) and adapted for the Elixir ecosystem.
