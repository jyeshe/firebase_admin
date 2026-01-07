defmodule FirebaseTestHelper do
  @moduledoc """
  Firebase test helper functions for integration tests.

  This module provides implementations of Firebase Auth functions
  that are not yet implemented in the main library.
  """

  require Logger

  @test_user_email "integration_test@example.com"

  @doc """
  Creates a test user in Firebase Auth.

  Creates a real user in Firebase and returns the Google-generated UID.
  If user with test email already exists, returns that user.
  """
  def create_user(user_params \\ %{}) do
    email = user_params[:email] || @test_user_email

    # First, try to get user by email to see if it already exists
    case get_user_by_email(email) do
      {:ok, user} ->
        # User already exists, return it
        {:ok, user}

      {:error, %{"error" => %{"message" => message}}} when is_binary(message) ->
        # Check if it's a "user not found" error, then create the user
        if String.contains?(message, "USER_NOT_FOUND") or String.contains?(message, "not found") do
          do_create_user(user_params)
        else
          {:error, %{"error" => %{"message" => message}}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a user by email from Firebase Auth.
  """
  def get_user_by_email(email) do
    with {:ok, _project_id} <- FirebaseAdmin.Auth.get_project_id(),
         {:ok, access_token} <- FirebaseAdmin.Auth.get_access_token() do
      url = "https://identitytoolkit.googleapis.com/v1/accounts:lookup"

      body =
        %{
          "email" => [email]
        }
        |> Jason.encode!()

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 200, body: %{"users" => [user | _]}}} ->
          {:ok, user}

        {:ok, %{status: 200, body: %{"users" => []}}} ->
          {:error, %{"error" => %{"message" => "USER_NOT_FOUND"}}}

        {:ok, %{status: 200, body: body}} when not is_map_key(body, "users") ->
          {:error, %{"error" => %{"message" => "USER_NOT_FOUND"}}}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Firebase Auth get_user_by_email failed: #{status} - #{inspect(body)}")
          {:error, body}

        {:error, reason} ->
          Logger.error("Firebase Auth get_user_by_email request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Gets a user by UID from Firebase Auth.
  """
  def get_user(uid) do
    with {:ok, _project_id} <- FirebaseAdmin.Auth.get_project_id(),
         {:ok, access_token} <- FirebaseAdmin.Auth.get_access_token() do
      url = "https://identitytoolkit.googleapis.com/v1/accounts:lookup"

      body =
        %{
          "localId" => [uid]
        }
        |> Jason.encode!()

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 200, body: %{"users" => [user | _]}}} ->
          {:ok, user}

        {:ok, %{status: 200, body: %{"users" => []}}} ->
          {:error, %{"error" => %{"message" => "USER_NOT_FOUND"}}}

        {:ok, %{status: 200, body: body}} when not is_map_key(body, "users") ->
          {:error, %{"error" => %{"message" => "USER_NOT_FOUND"}}}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Firebase Auth get_user failed: #{status} - #{inspect(body)}")
          {:error, body}

        {:error, reason} ->
          Logger.error("Firebase Auth get_user request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Creates a custom token for a user.
  """
  def create_custom_token(uid, custom_claims \\ %{}) do
    with {:ok, _project_id} <- FirebaseAdmin.Auth.get_project_id(),
         {:ok, service_account_email} <- FirebaseAdmin.Auth.get_service_account_email(),
         {:ok, private_key} <- FirebaseAdmin.Auth.get_private_key() do
      now = System.system_time(:second)

      _header = %{
        "alg" => "RS256",
        "typ" => "JWT"
      }

      payload = %{
        "iss" => service_account_email,
        "sub" => service_account_email,
        "aud" =>
          "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
        "uid" => uid,
        "iat" => now,
        "exp" => now + 3600,
        "claims" => custom_claims
      }

      # Create JWT using Joken
      signer = Joken.Signer.create("RS256", %{"pem" => private_key})

      case Joken.generate_and_sign(%{}, payload, signer) do
        {:ok, token, _claims} -> {:ok, token}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Deletes a test user.
  """
  def delete_user(uid) do
    with {:ok, _project_id} <- FirebaseAdmin.Auth.get_project_id(),
         {:ok, access_token} <- FirebaseAdmin.Auth.get_access_token() do
      url = "https://identitytoolkit.googleapis.com/v1/accounts:delete"

      body =
        %{
          "localId" => uid
        }
        |> Jason.encode!()

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 200}} ->
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.error("Firebase Auth delete_user failed: #{status} - #{inspect(body)}")
          {:error, body}

        {:error, reason} ->
          Logger.error("Firebase Auth delete_user request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Private functions

  defp do_create_user(user_params) do
    email = user_params[:email] || @test_user_email
    display_name = user_params[:display_name] || "Integration Test User"

    with {:ok, _project_id} <- FirebaseAdmin.Auth.get_project_id(),
         {:ok, access_token} <- FirebaseAdmin.Auth.get_access_token() do
      url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp"

      body =
        %{
          "email" => email,
          "displayName" => display_name,
          "emailVerified" => user_params[:email_verified] || false
        }
        |> Jason.encode!()

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          # Transform response to match expected format
          user = %{
            "uid" => response["localId"],
            "email" => response["email"],
            "displayName" => response["displayName"],
            "emailVerified" => response["emailVerified"] || false
          }

          {:ok, user}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Firebase Auth create_user failed: #{status} - #{inspect(body)}")
          {:error, body}

        {:error, reason} ->
          Logger.error("Firebase Auth create_user request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
