defmodule FirebaseAdmin.TokenVerifierTest do
  use ExUnit.Case, async: false

  alias FirebaseAdmin.TokenVerifier

  setup do
    # Initialize DETS table for tests
    TokenVerifier.ensure_initialized()

    # Clean up DETS table after each test
    on_exit(fn ->
      # Check if table is still open before trying to access it
      with :firebase_public_keys <- :dets.info(:firebase_public_keys, :filename) do
        :dets.delete_all_objects(:firebase_public_keys)
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

  describe "refresh_keys/0" do
    test "triggers key refresh" do
      assert :ok = TokenVerifier.refresh_keys()
    end
  end
end
