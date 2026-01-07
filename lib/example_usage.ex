defmodule ExampleUsage do
  @moduledoc """
  Example usage patterns for Firebase Admin SDK in a real application.

  This module demonstrates common patterns you might use in a Phoenix
  controller, LiveView, or background job processor.
  """

  @doc """
  Example: Authenticate a user from a Phoenix controller.

  In your controller:

      defmodule MyAppWeb.AuthController do
        use MyAppWeb, :controller

        def authenticate(conn, %{"id_token" => id_token}) do
          case ExampleUsage.authenticate_user(id_token) do
            {:ok, user_claims} ->
              conn
              |> put_session(:user_id, user_claims["sub"])
              |> put_session(:email, user_claims["email"])
              |> json(%{success: true, user_id: user_claims["sub"]})

            {:error, reason} ->
              conn
              |> put_status(:unauthorized)
              |> json(%{error: "Authentication failed", reason: reason})
          end
        end
      end
  """
  def authenticate_user(id_token) do
    case FirebaseAdmin.verify_token(id_token) do
      {:ok, claims} ->
        # Additional validation or user lookup can happen here
        {:ok, claims}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example: Sign out a user from all devices.

  Useful when a user changes their password or requests to be signed out everywhere.
  """
  def sign_out_user_everywhere(user_id) do
    case FirebaseAdmin.revoke_refresh_tokens(user_id) do
      :ok ->
        # Optionally clear any local sessions or caches
        {:ok, "User signed out from all devices"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Example: Send a notification to a user's device.

  This could be triggered by a background job, webhook, or user action.
  """
  def send_notification_to_user(device_token, title, body, data \\ %{}) do
    message = %{
      token: device_token,
      notification: %{
        title: title,
        body: body
      },
      data: data,
      android: %{
        priority: "high"
      },
      apns: %{
        payload: %{
          aps: %{
            sound: "default"
          }
        }
      }
    }

    FirebaseAdmin.send_message(message)
  end

  @doc """
  Example: Send a notification to all of a user's devices.

  Assumes you store device tokens in your database.
  """
  def notify_all_user_devices(user_id, title, body) do
    # Fetch all device tokens for the user from your database
    device_tokens = get_user_device_tokens(user_id)

    if length(device_tokens) > 0 do
      message = %{
        tokens: device_tokens,
        notification: %{
          title: title,
          body: body
        },
        data: %{
          "user_id" => user_id,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      case FirebaseAdmin.send_multicast(message) do
        {:ok, %{success_count: success, failure_count: failures, responses: responses}} ->
          # Clean up invalid tokens
          cleanup_invalid_tokens(device_tokens, responses)

          {:ok, %{sent: success, failed: failures}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, %{sent: 0, failed: 0}}
    end
  end

  @doc """
  Example: Generate a temporary download link for a private file.
  """
  def get_temporary_file_link(file_path, expires_in \\ 3600) do
    bucket = Application.get_env(:my_app, :firebase_bucket)
    FirebaseAdmin.Storage.get_signed_url(bucket, file_path, expires_in)
  end

  @doc """
  Example: Background job to send batch notifications.

  This could be used with Oban, Quantum, or similar job processors.
  """
  def send_batch_notifications(user_ids, notification_data) do
    user_ids
    |> Task.async_stream(
      fn user_id ->
        tokens = get_user_device_tokens(user_id)

        if length(tokens) > 0 do
          message = %{
            tokens: tokens,
            notification: %{
              title: notification_data.title,
              body: notification_data.body
            }
          }

          FirebaseAdmin.send_multicast(message)
        else
          {:ok, %{success_count: 0, failure_count: 0}}
        end
      end,
      max_concurrency: 5,
      timeout: 30_000
    )
    |> Enum.reduce({0, 0}, fn
      {:ok, {:ok, %{success_count: s, failure_count: f}}}, {total_s, total_f} ->
        {total_s + s, total_f + f}

      _, acc ->
        acc
    end)
  end

  # Example: Plug for authenticating requests with Firebase tokens.

  # Add to your router:

  #     pipeline :firebase_auth do
  #       plug ExampleUsage.FirebaseAuthPlug
  #     end
  defmodule FirebaseAuthPlug do
    @moduledoc "Example Firebase authentication plug - requires :plug dependency"

    # Commented out to avoid compilation error since Plug is not in dependencies
    # import Plug.Conn

    def init(opts), do: opts

    def call(_conn, _opts) do
      # Example implementation - requires :plug and :phoenix dependencies
      # case get_req_header(conn, "authorization") do
      #   ["Bearer " <> token] ->
      #     case FirebaseAdmin.verify_token(token) do
      #       {:ok, claims} ->
      #         conn
      #         |> assign(:current_user_id, claims["sub"])
      #         |> assign(:firebase_claims, claims)
      #
      #       {:error, _reason} ->
      #         conn
      #         |> put_status(:unauthorized)
      #         |> Phoenix.Controller.json(%{error: "Invalid token"})
      #         |> halt()
      #     end
      #
      #   _ ->
      #     conn
      #     |> put_status(:unauthorized)
      #     |> Phoenix.Controller.json(%{error: "Missing authorization header"})
      #     |> halt()
      # end
      raise "FirebaseAuthPlug requires :plug and :phoenix dependencies. Add them to your deps."
    end
  end

  # Private helper functions (you'd implement these based on your database)

  defp get_user_device_tokens(_user_id) do
    # Query your database for user's device tokens
    # Example with Ecto:
    # from(d in DeviceToken, where: d.user_id == ^user_id, select: d.token)
    # |> Repo.all()
    []
  end

  defp cleanup_invalid_tokens(_tokens, _responses) do
    # Remove invalid tokens from your database
    # Iterate through responses and delete tokens that returned
    # errors like "InvalidRegistration" or "NotRegistered"
    :ok
  end
end
