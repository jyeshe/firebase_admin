# Start ExUnit with integration test configuration
ExUnit.start()

# Set Mix environment to integration_test
Mix.env(:integration_test)

# Helper functions for integration tests
defmodule FirebaseAdmin.IntegrationTestHelper do
  @moduledoc """
  Helper functions for Firebase integration tests that interact with real Firebase services.
  """

  @doc """
  Checks if integration test environment is properly configured.
  """
  def configured?() do
    case File.read("firebase-sa-test.json") do
      {:error, :enoent} ->
        IO.puts("Warning: firebase-sa-test.json file not found in project root")
        false

      {:error, reason} ->
        IO.puts("Error: Could not read firebase-sa-test.json: #{reason}")
        false

      {:ok, json_content} ->
        try do
          Jason.decode!(json_content)
          true
        rescue
          _ ->
            IO.puts("Error: Invalid JSON in firebase-sa-test.json")
            false
        end
    end
  end

  def project_id do
    {:ok, project_id} = FirebaseAdmin.Auth.get_project_id()
    project_id
  end

  @doc """
  Gets the FCM sender ID from configuration.
  """
  def fcm_sender_id() do
    Application.get_env(:firebase_admin, :fcm_sender_id, "")
  end

  @doc """
  Creates a test FCM token (mock token for testing).
  Note: In real integration tests, you'd use actual device tokens.
  """
  def test_fcm_token() do
    "integration_test_token_#{System.unique_integer([:positive])}"
  end

  @doc """
  Sets up test data and cleans up after tests.
  """
  def setup_integration_test() do
    unless configured?() do
      throw("Integration tests require firebase-sa-test.json file in project root")
    end

    # Load credentials at runtime and configure the application
    {:ok, json_content} = File.read("firebase-sa-test.json")
    credentials = Jason.decode!(json_content)
    # Set up configuration from the service account file
    Application.put_env(:firebase_admin, :credentials, credentials)
    # Configure Goth with credentials
    Application.put_env(:goth, :json, json_content)
  end

  @doc """
  Generates a unique test email for user creation tests.
  """
  def test_email() do
    timestamp = System.system_time(:microsecond)
    "integration_test_#{timestamp}@example.com"
  end

  @doc """
  Cleanup helper to remove test users created during integration tests.
  """
  def cleanup_test_user(uid) when is_binary(uid) do
    # Note: This will be implemented when Auth functions are available
    # For now, just return :ok
    :ok
  end

  @doc """
  Helper to skip integration tests if not properly configured.
  """
  defmacro integration_test(description, do: block) do
    quote do
      test unquote(description) do
        FirebaseAdmin.IntegrationTestHelper.setup_integration_test()
        unquote(block)
      end
    end
  end
end
