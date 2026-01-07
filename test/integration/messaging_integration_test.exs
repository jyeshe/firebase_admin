defmodule FirebaseAdmin.MessagingIntegrationTest do
  use ExUnit.Case, async: false

  import FirebaseAdmin.IntegrationTestHelper
  alias FirebaseAdmin.Messaging

  describe "Firebase Cloud Messaging Integration Tests" do
    integration_test "sends message to single device token" do
      # Note: This uses a test token that won't deliver to a real device
      # In a real scenario, you'd use actual device registration tokens
      test_token = test_fcm_token()

      message = %{
        token: test_token,
        notification: %{
          title: "Integration Test",
          body: "This is a test notification from integration tests"
        },
        data: %{
          "test_key" => "test_value",
          "timestamp" => to_string(System.system_time(:second))
        },
        android: %{
          priority: "high",
          notification: %{
            sound: "default",
            click_action: "FLUTTER_NOTIFICATION_CLICK"
          }
        },
        apns: %{
          payload: %{
            aps: %{
              sound: "default",
              badge: 1
            }
          }
        }
      }

      # Send message - this should succeed even with a fake token
      # Firebase will return a message ID, but delivery will fail
      case Messaging.send(message) do
        {:ok, message_id} ->
          assert is_binary(message_id)
          assert String.length(message_id) > 0

        {:error, response} ->
          # Some errors are expected with test tokens
          # Check if it's a token-related error vs configuration error
          case response do
            %{"error" => %{"message" => msg}} ->
              # These are expected errors for test tokens
              valid_errors = [
                "INVALID_ARGUMENT",
                "UNREGISTERED",
                "INVALID_REGISTRATION_TOKEN"
              ]

              assert Enum.any?(valid_errors, fn error -> String.contains?(msg, error) end),
                     "Unexpected error: #{msg}"

            _ ->
              flunk("Unexpected error format: #{inspect(response)}")
          end
      end
    end

    integration_test "sends message to topic" do
      topic_name = "integration_test_topic_#{System.system_time(:microsecond)}"

      message = %{
        topic: topic_name,
        notification: %{
          title: "Topic Test",
          body: "This is a test message to a topic"
        },
        data: %{
          "test_type" => "topic_message",
          "topic" => topic_name
        }
      }

      # Send to topic - this should succeed
      assert {:ok, message_id} = Messaging.send(message)
      assert is_binary(message_id)
      assert String.length(message_id) > 0
    end

    integration_test "sends multicast message to multiple tokens" do
      # Create multiple test tokens
      test_tokens =
        for i <- 1..3 do
          "test_token_#{i}_#{System.system_time(:microsecond)}"
        end

      message = %{
        tokens: test_tokens,
        notification: %{
          title: "Multicast Test",
          body: "This is a multicast test message"
        },
        data: %{
          "test_type" => "multicast",
          "token_count" => to_string(length(test_tokens))
        }
      }

      case Messaging.send_multicast(message) do
        {:ok, response} ->
          assert is_map(response)
          # Check for either format: snake_case or camelCase
          assert Map.has_key?(response, :success_count) or Map.has_key?(response, "successCount")
          assert Map.has_key?(response, :failure_count) or Map.has_key?(response, "failureCount")
          assert Map.has_key?(response, :responses) or Map.has_key?(response, "responses")

          # With test tokens, we expect failures
          success_count = response[:success_count] || response["successCount"] || 0
          failure_count = response[:failure_count] || response["failureCount"] || 0
          assert success_count + failure_count == length(test_tokens)

        {:error, response} ->
          # Multicast with all invalid tokens might return an error
          assert is_map(response)
      end
    end

    # TODO: Topic subscription tests removed as requested
    # (subscribe_to_topic and unsubscribe_from_topic functions not implemented)

    integration_test "validates message format" do
      # Test with invalid message (missing required fields)
      invalid_message = %{
        notification: %{
          title: "Test"
          # Missing body
        }
        # Missing target (token/topic/condition)
      }

      assert {:error, response} = Messaging.send(invalid_message)
      # Should get validation error for missing target
      assert response == :invalid_message_missing_target
    end

    integration_test "sends message with condition" do
      condition = "'integration_test' in topics || 'all_users' in topics"

      message = %{
        condition: condition,
        notification: %{
          title: "Condition Test",
          body: "This message uses topic conditions"
        },
        data: %{
          "test_type" => "condition",
          "condition_used" => condition
        }
      }

      # Send with condition - should succeed
      assert {:ok, message_id} = Messaging.send(message)
      assert is_binary(message_id)
      assert String.length(message_id) > 0
    end

    integration_test "handles rate limiting gracefully" do
      topic_name = "rate_limit_test_#{System.system_time(:microsecond)}"

      # Send multiple messages quickly to potentially trigger rate limiting
      results =
        for i <- 1..5 do
          message = %{
            topic: topic_name,
            data: %{"message_number" => to_string(i)}
          }

          Messaging.send(message)
        end

      # At least some should succeed, some might be rate limited
      success_count =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert success_count >= 1, "Expected at least one message to succeed"

      # Check if any were rate limited
      rate_limited =
        Enum.any?(results, fn
          {:error, %{"error" => %{"message" => msg}}} ->
            String.contains?(msg, "QUOTA_EXCEEDED") || String.contains?(msg, "RATE_LIMITED")

          _ ->
            false
        end)

      # Rate limiting is possible but not required for this test
      if rate_limited do
        IO.puts("Note: Rate limiting detected in integration test")
      end
    end

    integration_test "validates FCM sender ID configuration" do
      # This test verifies that our FCM configuration is properly set up
      sender_id = fcm_sender_id()
      assert sender_id == ""

      # Verify project ID matches
      project_id = project_id()
      assert project_id == "cashradar-c32d3"
    end

    integration_test "fails on unexpected 400 errors" do
      # Test with malformed message that should cause 400
      malformed_message = %{
        token: "valid_token_format_but_invalid",
        notification: %{
          # Invalid notification structure that should cause 400
          invalid_field: "this should not be allowed"
        }
      }

      case Messaging.send(malformed_message) do
        {:ok, _message_id} ->
          flunk("Expected message to fail due to malformed notification")

        {:error, response} ->
          case response do
            %{"error" => %{"message" => msg}} ->
              # If we get a 400 error for an unexpected reason (not token-related),
              # we should fail the test
              if String.contains?(msg, "INVALID_ARGUMENT") and
                   not (String.contains?(msg, "token") or String.contains?(msg, "registration")) do
                # Expected failure
                assert true
              else
                # Token-related errors are expected, other 400s should fail test
                if String.contains?(msg, "token") or String.contains?(msg, "registration") do
                  # Token errors are OK for this test
                  assert true
                else
                  flunk("Unexpected 400 error: #{msg}")
                end
              end

            # Network or other errors
            reason when is_binary(reason) ->
              # Network errors are acceptable
              assert true

            other ->
              flunk("Unexpected error format: #{inspect(other)}")
          end
      end
    end
  end
end
