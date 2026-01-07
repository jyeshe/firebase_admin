defmodule FirebaseAdmin.TokenRevocation do
  @moduledoc """
  Handles refresh token revocation for Firebase users.

  This module provides functionality to revoke all refresh tokens for a user,
  effectively signing them out from all devices.
  """

  require Logger
  alias FirebaseAdmin.Auth

  @identity_toolkit_base_url "https://identitytoolkit.googleapis.com/v1"

  @doc """
  Revokes all refresh tokens for a user.

  This sets the user's `validSince` time to the current timestamp, invalidating
  all tokens issued before this time.

  ## Parameters

    - `uid` - The Firebase user ID

  ## Returns

    - `:ok` - Tokens successfully revoked
    - `{:error, reason}` - Revocation failed

  ## Examples

      iex> FirebaseAdmin.TokenRevocation.revoke("user123")
      :ok

      iex> FirebaseAdmin.TokenRevocation.revoke("nonexistent")
      {:error, "USER_NOT_FOUND"}
  """
  @spec revoke(String.t()) :: :ok | {:error, term()}
  def revoke(uid) when is_binary(uid) do
    with {:ok, project_id} <- Auth.get_project_id(),
         {:ok, access_token} <- Auth.get_access_token() do
      do_revoke(uid, project_id, access_token)
    end
  end

  defp do_revoke(uid, project_id, access_token) do
    url = "#{@identity_toolkit_base_url}/projects/#{project_id}/accounts:update"

    body = %{
      localId: uid,
      # Set validSince to current timestamp (in seconds)
      validSince: System.system_time(:second)
    }

    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200}} ->
        Logger.info("Successfully revoked refresh tokens for user: #{uid}")
        :ok

      {:ok, %{status: status, body: body}} ->
        error = parse_error(body)
        Logger.error("Failed to revoke tokens for user #{uid}: #{status} - #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.error("Request failed while revoking tokens for user #{uid}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_error(%{"error" => %{"message" => message}}), do: message
  defp parse_error(%{"error" => error}) when is_binary(error), do: error
  defp parse_error(body), do: body
end
