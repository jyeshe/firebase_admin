defmodule FirebaseAdmin.FCMIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  import FirebaseAdmin.IntegrationTestHelper
  alias FirebaseAdmin.FCM
  alias FirebaseAdmin.FCM.Message

  describe "Firebase Cloud Messaging Integration Tests" do
    integration_test "sends message to single device token" do
      # Note: This uses a test token that won't deliver to a real device
      # In a real scenario, you'd use actual device registration tokens
      Message.build_for_device(
        test_fcm_token(),
        %{
          title: "Integration Test",
          body: "This is a test notification from integration tests"
        },
        %{
          "test_key" => "test_value",
          "timestamp" => to_string(System.system_time(:second))
        },
        android: %{
          notification: %{
            sound: "default",
            click_action: "FLUTTER_NOTIFICATION_CLICK"
          }
        }
      )
      |> FCM.send()
      |> case do
        {:ok, message_id} ->
          assert is_binary(message_id)
          assert String.length(message_id) > 0

        {:error, response} ->
          # Some errors are expected with test tokens
          # Check if it's a token-related error vs configuration error
          case response do
            %{message: msg} when is_binary(msg) ->
              # These are expected errors for test tokens
              valid_errors = [
                "INVALID_ARGUMENT",
                "UNREGISTERED", 
                "registration token"
              ]

              assert Enum.any?(valid_errors, fn error -> String.contains?(msg, error) end),
                     "Unexpected error: #{msg}"

            %{"message" => msg} when is_binary(msg) ->
              # These are expected errors for test tokens  
              valid_errors = [
                "INVALID_ARGUMENT",
                "UNREGISTERED",
                "registration token"
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

      message = Message.build_for_topic(
        topic_name,
        %{
          title: "Topic Test",
          body: "This is a test message to a topic"
        },
        %{
          "test_type" => "topic_message"
        }
      )

      # Send to topic - this should succeed
      assert {:ok, message_id} = FCM.send(message)
      assert is_binary(message_id)
      assert String.length(message_id) > 0
    end

    integration_test "sends multicast message to multiple tokens" do
      # Create multiple test tokens
      test_tokens =
        for i <- 1..3 do
          "test_token_#{i}_#{System.system_time(:microsecond)}"
        end

      message =
        Message.build_for_multicast(
          test_tokens,
          %{
            title: "Multicast Test",
            body: "This is a multicast test message"
          },
          %{
            "test_type" => "multicast",
            "token_count" => to_string(length(test_tokens))
          }
        )

      case FCM.send_multicast(message) do
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
      # Test with invalid device token
      invalid_message = Message.build_for_device(
        "fake-device-token",
        %{
          title: "Test",
          body: "Test message"
        }
      )

      assert {:error, response} = FCM.send(invalid_message)
      # Should get validation error for invalid token
      case response do
        %{"message" => message} when is_binary(message) ->
          assert String.contains?(message, "registration token")
        %{message: message} when is_binary(message) ->
          assert String.contains?(message, "registration token")
        _ ->
          flunk("Expected FCM error with token validation message")
      end
    end

    integration_test "sends message with condition" do
      condition = "'integration_test' in topics || 'all_users' in topics"

      message = Message.build_for_condition(
        condition,
        %{
          title: "Condition Test",
          body: "This message uses topic conditions"
        },
        %{
          "test_type" => "condition",
          "condition_used" => condition
        }
      )

      # Send with condition - should succeed
      assert {:ok, message_id} = FCM.send(message)
      assert is_binary(message_id)
      assert String.length(message_id) > 0
    end
  end
end
