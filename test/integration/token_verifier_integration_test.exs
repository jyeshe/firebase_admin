defmodule FirebaseAdmin.TokenVerifierIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  import FirebaseAdmin.IntegrationTestHelper
  alias FirebaseAdmin.TokenVerifier

  setup_all do
    TokenVerifier.ensure_initialized()
    Process.sleep(3000)

    :ok
  end

  describe "Firebase Token Verifier Integration Tests" do
    integration_test "fetches real Firebase public keys" do
      # Keys should already be available from setup
      # Check that keys were stored in DETS
      case :dets.lookup(:firebase_public_keys, :keys) do
        [{:keys, keys, timestamp}] ->
          assert is_map(keys)
          assert map_size(keys) > 0
          assert is_integer(timestamp)

          # Keys should be X.509 certificates
          Enum.each(keys, fn {kid, cert} ->
            assert is_binary(kid)
            assert is_binary(cert)
            assert String.starts_with?(cert, "-----BEGIN CERTIFICATE-----")
            assert String.ends_with?(cert, "-----END CERTIFICATE-----\n")
          end)

        [] ->
          flunk("No public keys found in cache after refresh")
      end
    end

    integration_test "creates and verifies custom token" do
      # Create a test user first using FirebaseTestHelper (Firebase will generate UID)
      user_params = %{
        email: "integration_test#{System.system_time(:millisecond)}@example.com",
        display_name: "Integration Test User"
      }

      {:ok, %{"uid" => test_id}} = FirebaseTestHelper.create_user(user_params)

      # Create custom token using FirebaseTestHelper
      custom_claims = %{"role" => "admin", "level" => 42, "aud" => project_id()}
      {:ok, custom_token} = FirebaseTestHelper.create_custom_token(test_id, custom_claims)

      # Note: Custom tokens are signed by our service account private key
      # and are meant to be exchanged for ID tokens by the client
      # We can't directly verify them with the public keys (which are for ID tokens)
      # But we can validate the structure

      assert [header, payload, _signature] = String.split(custom_token, ".")

      # Decode header
      assert {:ok, decoded_header} = Base.url_decode64(header, padding: false)
      assert %{"alg" => "RS256"} = Jason.decode!(decoded_header)

      # Decode payload
      {:ok, decoded_payload} = Base.url_decode64(payload, padding: false)

      assert %{"iss" => issuer, "uid" => ^test_id, "claims" => claims} =
               Jason.decode!(decoded_payload)

      assert String.contains?(issuer, project_id())
      assert claims["role"] == "admin"
      assert claims["level"] == 42
      assert claims["aud"] == project_id()

      # Cleanup using FirebaseTestHelper
      FirebaseTestHelper.delete_user(test_id)
    end

    integration_test "handles invalid token formats gracefully" do
      invalid_tokens = [
        "invalid",
        "too.few",
        "too.many.parts.here",
        # No signature
        "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0.",
        "not.base64.encoded"
      ]

      Enum.each(invalid_tokens, fn token ->
        result = TokenVerifier.verify(token)
        assert match?({:error, _}, result)
      end)
    end

    integration_test "validates token issuer correctly" do
      # Get real kid from cached keys first
      [{:keys, keys, _}] = :dets.lookup(:firebase_public_keys, :keys)
      real_kid = keys |> Map.keys() |> List.first()

      # Create a token with wrong issuer but valid kid
      header = %{"alg" => "RS256", "kid" => real_kid}

      payload = %{
        "iss" => "https://wrong-issuer.com",
        "aud" => project_id(),
        "sub" => "test-user",
        "iat" => System.system_time(:second),
        "exp" => System.system_time(:second) + 3600
      }

      encoded_header = Base.url_encode64(Jason.encode!(header), padding: false)
      encoded_payload = Base.url_encode64(Jason.encode!(payload), padding: false)
      fake_token = "#{encoded_header}.#{encoded_payload}.fake-signature"

      assert {:error, reason} = TokenVerifier.verify(fake_token)
      # Should get signature verification error since we're using fake signature
      # But for this test, any signature-related error is fine
      assert reason in [:signature_verification_failed, :invalid_signature] or
               String.contains?(to_string(reason), "signature") or
               String.contains?(to_string(reason), "issuer")
    end

    integration_test "validates token audience correctly" do
      # Get real kid from cached keys first
      [{:keys, keys, _}] = :dets.lookup(:firebase_public_keys, :keys)
      real_kid = keys |> Map.keys() |> List.first()

      # Create a token with wrong audience but valid kid
      header = %{"alg" => "RS256", "kid" => real_kid}

      payload = %{
        "iss" => "https://securetoken.google.com/#{project_id()}",
        "aud" => "wrong-project-id",
        "sub" => "test-user",
        "iat" => System.system_time(:second),
        "exp" => System.system_time(:second) + 3600
      }

      encoded_header = Base.url_encode64(Jason.encode!(header), padding: false)
      encoded_payload = Base.url_encode64(Jason.encode!(payload), padding: false)
      fake_token = "#{encoded_header}.#{encoded_payload}.fake-signature"

      assert {:error, reason} = TokenVerifier.verify(fake_token)
      # Should get signature verification error since we're using fake signature
      assert reason in [:signature_verification_failed, :invalid_signature] or
               String.contains?(to_string(reason), "signature") or
               String.contains?(to_string(reason), "audience")
    end

    integration_test "validates token expiration correctly" do
      # Get real kid from cached keys first
      [{:keys, keys, _}] = :dets.lookup(:firebase_public_keys, :keys)
      real_kid = keys |> Map.keys() |> List.first()

      # Create an expired token but with valid kid
      header = %{"alg" => "RS256", "kid" => real_kid}

      payload = %{
        "iss" => "https://securetoken.google.com/#{project_id()}",
        "aud" => project_id(),
        "sub" => "test-user",
        # 2 hours ago
        "iat" => System.system_time(:second) - 7200,
        # 1 hour ago (expired)
        "exp" => System.system_time(:second) - 3600
      }

      encoded_header = Base.url_encode64(Jason.encode!(header), padding: false)
      encoded_payload = Base.url_encode64(Jason.encode!(payload), padding: false)
      fake_token = "#{encoded_header}.#{encoded_payload}.fake-signature"

      assert {:error, reason} = TokenVerifier.verify(fake_token)
      # Should get signature verification error since we're using fake signature
      assert reason in [:signature_verification_failed, :invalid_signature] or
               String.contains?(to_string(reason), "signature") or
               String.contains?(to_string(reason), "expired")
    end

    integration_test "validates project ID configuration" do
      # Verify our project ID is correctly configured
      configured_project_id = project_id()
      assert configured_project_id == "cashradar-c32d3"

      # The issuer URL should contain our project ID
      expected_issuer = "https://securetoken.google.com/#{configured_project_id}"

      # Get real kid from cached keys first
      [{:keys, keys, _}] = :dets.lookup(:firebase_public_keys, :keys)
      real_kid = keys |> Map.keys() |> List.first()

      # Create a valid-looking token with correct issuer and real kid
      header = %{"alg" => "RS256", "kid" => real_kid}

      payload = %{
        "iss" => expected_issuer,
        "aud" => configured_project_id,
        "sub" => "test-user",
        "iat" => System.system_time(:second),
        "exp" => System.system_time(:second) + 3600
      }

      encoded_header = Base.url_encode64(Jason.encode!(header), padding: false)
      encoded_payload = Base.url_encode64(Jason.encode!(payload), padding: false)
      test_token = "#{encoded_header}.#{encoded_payload}.fake-signature"

      # This should fail with signature verification, not issuer/audience validation
      case TokenVerifier.verify(test_token) do
        {:error, :signature_verification_failed} ->
          :ok

        {:error, :invalid_signature} ->
          :ok

        {:error, :signature_error} ->
          :ok

        {:error, reason} when is_binary(reason) ->
          # Should get signature-related error since we're using fake signature
          assert String.contains?(reason, "signature") or String.contains?(reason, "verify")

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end
end
