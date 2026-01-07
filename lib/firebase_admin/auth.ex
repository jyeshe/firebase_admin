defmodule FirebaseAdmin.Auth do
  @moduledoc """
  Handles authentication and authorization for Firebase Admin SDK.

  This module manages Google service account credentials and generates
  access tokens for authenticating with Firebase services.
  """

  require Logger

  @doc """
  Gets an access token for Firebase Admin operations.

  Uses Goth to obtain an OAuth2 access token from the service account credentials.

  ## Returns

    - `{:ok, token}` - Successfully obtained access token
    - `{:error, reason}` - Failed to get token
  """
  @spec get_access_token() :: {:ok, String.t()} | {:error, term()}
  def get_access_token do
    case get_goth_token() do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the project ID from configuration.

  ## Returns

    - `{:ok, project_id}` - Project ID found
    - `{:error, :no_credentials_project}` - Project ID not configured
  """
  @spec get_project_id() :: {:ok, String.t()} | {:error, :no_credentials_project}
  def get_project_id do
    with nil <- :persistent_term.get({__MODULE__, :project_id}, nil) do
      case get_credentials() do
        {:ok, %{"project_id" => project_id}} ->
          :persistent_term.put({__MODULE__, :project_id}, {:ok, project_id})
          {:ok, project_id}

        _error -> {:error, :no_credentials_project}
      end
    end
  end

  @doc """
  Gets the service account email from credentials.

  ## Returns

    - `{:ok, email}` - Service account email
    - `{:error, reason}` - Failed to get email
  """
  @spec get_service_account_email() :: {:ok, String.t()} | {:error, term()}
  def get_service_account_email do
    case get_credentials() do
      {:ok, %{"client_email" => email}} -> {:ok, email}
      {:ok, _} -> {:error, :no_client_email}
      error -> error
    end
  end

  @doc """
  Gets the private key from credentials for signing operations.

  ## Returns

    - `{:ok, private_key}` - Private key string
    - `{:error, reason}` - Failed to get private key
  """
  @spec get_private_key() :: {:ok, String.t()} | {:error, term()}
  def get_private_key do
    case get_credentials() do
      {:ok, %{"private_key" => key}} -> {:ok, key}
      {:ok, _} -> {:error, :no_private_key}
      error -> error
    end
  end

  # Private functions

  defp get_goth_token do
    with {:ok, credentials} <- get_credentials() do
      Goth.Token.fetch(credentials)
    end
  end

  defp get_credentials do
    case Application.get_env(:firebase_admin, :credentials) do
      nil ->
        {:error, :no_credentials}

      path when is_binary(path) ->
        load_credentials_from_file(path)

      credentials when is_map(credentials) ->
        {:ok, credentials}

      other ->
        Logger.error("Invalid credentials configuration: #{inspect(other)}")
        {:error, :invalid_credentials}
    end
  end

  defp load_credentials_from_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, credentials} -> {:ok, credentials}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:error, reason} ->
        Logger.error("Failed to read credentials file: #{inspect(reason)}")
        {:error, {:file_read_error, reason}}
    end
  end
end
