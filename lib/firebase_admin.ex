defmodule FirebaseAdmin do
  @moduledoc """
  Firebase Admin SDK for Elixir.

  This library provides a subset of Firebase Admin SDK functionality for Elixir applications:

  - ID Token Verification
  - Refresh Token Revocation
  - Firebase Cloud Messaging (FCM)
  - FCM Multicast
  - Cloud Storage

  ## Configuration

  Add your Firebase service account credentials to your config:

      config :firebase_admin,
        project_id: "your-project-id",
        credentials: "path/to/service-account.json"
        # OR
        credentials: %{
          "type" => "service_account",
          "project_id" => "your-project",
          "private_key_id" => "...",
          "private_key" => "...",
          "client_email" => "...",
          "client_id" => "...",
          "auth_uri" => "...",
          "token_uri" => "...",
          "auth_provider_x509_cert_url" => "...",
          "client_x509_cert_url" => "..."
        }

  ## Usage Examples

      # Verify an ID token
      case FirebaseAdmin.verify_token(id_token) do
        {:ok, claims} -> IO.inspect(claims)
        {:error, reason} -> IO.puts("Verification failed: \#{reason}")
      end

      # Send a message
      message = %{
        token: "device_token",
        notification: %{
          title: "Hello",
          body: "World"
        }
      }
      FirebaseAdmin.send_message(message)

      # Send multicast
      message = %{
        tokens: ["token1", "token2", "token3"],
        notification: %{
          title: "Hello",
          body: "World"
        }
      }
      FirebaseAdmin.send_multicast(message)
  """

  alias FirebaseAdmin.TokenVerifier
  alias FirebaseAdmin.TokenRevocation
  alias FirebaseAdmin.Messaging

  @doc """
  Verifies a Firebase ID token and returns the decoded claims.

  ## Parameters

    - `token` - The Firebase ID token string to verify

  ## Returns

    - `{:ok, claims}` - Successfully verified token with claims map
    - `{:error, reason}` - Verification failed with reason

  ## Examples

      iex> FirebaseAdmin.verify_token("eyJhbGciOiJSUzI1...")
      {:ok, %{"sub" => "user123", "email" => "user@example.com", ...}}

      iex> FirebaseAdmin.verify_token("invalid")
      {:error, :invalid_token}
  """
  @spec verify_token(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def verify_token(token) do
    TokenVerifier.verify(token)
  end

  @doc """
  Revokes all refresh tokens for a user, effectively signing them out from all devices.

  ## Parameters

    - `uid` - The Firebase user ID

  ## Returns

    - `:ok` - Tokens successfully revoked
    - `{:error, reason}` - Revocation failed

  ## Examples

      iex> FirebaseAdmin.revoke_refresh_tokens("user123")
      :ok
  """
  @spec revoke_refresh_tokens(String.t()) :: :ok | {:error, term()}
  def revoke_refresh_tokens(uid) do
    TokenRevocation.revoke(uid)
  end

  @doc """
  Sends a message to a single device via Firebase Cloud Messaging.

  ## Parameters

    - `message` - A map containing the message payload

  ## Message structure

      %{
        token: "device_token",              # Required
        notification: %{                    # Optional
          title: "Title",
          body: "Body",
          image: "https://..."
        },
        data: %{                           # Optional
          "key1" => "value1",
          "key2" => "value2"
        },
        android: %{...},                   # Optional Android-specific options
        apns: %{...},                      # Optional iOS-specific options
        webpush: %{...}                    # Optional Web-specific options
      }

  ## Returns

    - `{:ok, message_id}` - Message successfully sent
    - `{:error, reason}` - Send failed

  ## Examples

      iex> message = %{
      ...>   token: "device_token",
      ...>   notification: %{title: "Hello", body: "World"}
      ...> }
      iex> FirebaseAdmin.send_message(message)
      {:ok, "projects/myproject/messages/1234567890"}
  """
  @spec send_message(map()) :: {:ok, String.t()} | {:error, term()}
  def send_message(message) do
    Messaging.send(message)
  end

  @doc """
  Sends a message to multiple devices (multicast).

  This is optimized to send messages concurrently while respecting rate limits.

  ## Parameters

    - `message` - A map containing the message payload with multiple tokens

  ## Message structure

      %{
        tokens: ["token1", "token2", "token3"],  # Required: list of tokens
        notification: %{...},                     # Optional
        data: %{...},                             # Optional
        android: %{...},                          # Optional
        apns: %{...},                             # Optional
        webpush: %{...}                           # Optional
      }

  ## Returns

    - `{:ok, results}` - Map containing success_count, failure_count, and responses

  ## Examples

      iex> message = %{
      ...>   tokens: ["token1", "token2"],
      ...>   notification: %{title: "Hello", body: "World"}
      ...> }
      iex> FirebaseAdmin.send_multicast(message)
      {:ok, %{
        success_count: 1,
        failure_count: 1,
        responses: [
          {:ok, "message_id_1"},
          {:error, "InvalidRegistration"}
        ]
      }}
  """
  @spec send_multicast(map()) :: {:ok, map()} | {:error, term()}
  def send_multicast(message) do
    Messaging.send_multicast(message)
  end
end
