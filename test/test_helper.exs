ExUnit.start()

# Exclude integration tests by default
# Use --include integration to run them
ExUnit.configure(exclude: [integration: true])

# Always load integration test helper
Code.require_file("integration_test_helper.exs", __DIR__)

# Helper functions for tests
defmodule FirebaseAdmin.TestHelper do
  @moduledoc false

  def generate_test_token do
    # This is a dummy token structure for testing
    # In real tests, you'd want to use proper JWT generation
    header = Jason.encode!(%{"alg" => "RS256", "kid" => "test-kid"})

    payload =
      Jason.encode!(%{
        "iss" => "https://securetoken.google.com/test-project",
        "aud" => "test-project",
        "sub" => "test-user-123",
        "iat" => System.system_time(:second),
        "exp" => System.system_time(:second) + 3600
      })

    encoded_header = Base.url_encode64(header, padding: false)
    encoded_payload = Base.url_encode64(payload, padding: false)

    "#{encoded_header}.#{encoded_payload}.fake-signature"
  end

  def mock_google_public_keys do
    %{
      "test-kid" => """
      -----BEGIN CERTIFICATE-----
      MIIDHDCCAgSgAwIBAgIIW...fake certificate...
      -----END CERTIFICATE-----
      """
    }
  end
end
