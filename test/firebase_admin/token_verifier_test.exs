defmodule FirebaseAdmin.TokenVerifierTest do
  use ExUnit.Case, async: false

  alias FirebaseAdmin.TokenVerifier

  setup do
    # Clean up DETS table after each test
    on_exit(fn ->
      case :dets.lookup(:firebase_public_keys, :keys) do
        [{:keys, _, _}] -> :dets.delete(:firebase_public_keys, :keys)
        [] -> :ok
      end
    end)

    :ok
  end

  describe "verify/1" do
    test "returns error for invalid token format" do
      assert {:error, _} = TokenVerifier.verify("invalid")
    end

    test "returns error for token without proper structure" do
      assert {:error, :invalid_token_format} = TokenVerifier.verify("no-dots-here")
    end

    test "returns error when no public keys available" do
      # This will happen if keys haven't been fetched yet
      token = "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2lkIn0.eyJzdWIiOiJ0ZXN0In0.signature"

      # Result depends on whether keys have been cached
      result = TokenVerifier.verify(token)
      assert match?({:error, _}, result)
    end
  end

  describe "key caching" do
    test "stores and retrieves keys from DETS" do
      test_keys = %{"key1" => "value1", "key2" => "value2"}

      # Manually insert into DETS
      :dets.insert(
        :firebase_public_keys,
        {:keys, test_keys, DateTime.utc_now() |> DateTime.to_unix()}
      )

      # Verify we can read it back
      [{:keys, stored_keys, _timestamp}] = :dets.lookup(:firebase_public_keys, :keys)
      assert stored_keys == test_keys
    end
  end

  describe "refresh_keys/0" do
    test "triggers key refresh" do
      assert :ok = TokenVerifier.refresh_keys()
    end
  end
end
