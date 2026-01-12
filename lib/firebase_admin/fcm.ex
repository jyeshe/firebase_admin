defmodule FirebaseAdmin.FCM do
  @moduledoc """
  Firebase Cloud Messaging (FCM) implementation.

  Provides functionality to send messages to devices via FCM, including
  single device messaging and multicast to multiple devices.
  """

  require Logger
  alias FirebaseAdmin.Auth
  alias FirebaseAdmin.FCM.Message

  @fcm_base_url "https://fcm.googleapis.com/v1"
  @max_multicast_size 500
  @max_concurrent_requests 10

  @doc """
  Sends a message to a single device.

  ## Returns

    - `{:ok, message_id}` - Message sent successfully
    - `{:error, reason}` - Send failed
  """
  @spec send(Message.t()) :: {:ok, String.t()} | {:error, term()}
  def send(message) do
    with {:ok, project_id} <- Auth.get_project_id(),
         {:ok, access_token} <- Auth.get_access_token() do
      send_message(message, project_id, access_token)
    end
  end

  @doc """
  Sends a message to multiple devices (multicast).

  Optimized to send messages concurrently while respecting rate limits.
  Automatically batches large token lists.

  ## Parameters

    - `message` - Map containing the message configuration with multiple tokens

  ## Message structure

      %{
        tokens: ["token1", "token2", "token3"],  # Required
        notification: %{...},                     # Optional
        data: %{...},                             # Optional
        android: %{...},                          # Optional
        apns: %{...},                             # Optional
        webpush: %{...}                           # Optional
      }

  ## Returns

    - `{:ok, results}` - Map with success_count, failure_count, and responses

  ## Example response

      {:ok, %{
        success_count: 2,
        failure_count: 1,
        responses: [
          {:ok, "projects/myproject/messages/msg1"},
          {:ok, "projects/myproject/messages/msg2"},
          {:error, "InvalidRegistration"}
        ]
      }}
  """
  @spec send_multicast(map()) :: {:ok, map()} | {:error, term()}
  def send_multicast(%{tokens: tokens} = message) when is_list(tokens) do
    if length(tokens) == 0 do
      {:error, :no_tokens}
    else
      with :ok <- validate_multicast_message(message),
           {:ok, project_id} <- Auth.get_project_id(),
           {:ok, access_token} <- Auth.get_access_token() do
        do_multicast(tokens, message, project_id, access_token)
      end
    end
  end

  def send_multicast(_), do: {:error, :missing_tokens}

  # Private functions
  defp validate_multicast_message(%{tokens: tokens}) when is_list(tokens) do
    cond do
      not Enum.all?(tokens, &is_binary/1) ->
        {:error, :invalid_tokens_must_be_strings}

      length(tokens) > @max_multicast_size ->
        {:error, :too_many_tokens}

      true ->
        :ok
    end
  end

  defp validate_multicast_message(_), do: {:error, :missing_tokens}

  defp send_message(message, project_id, access_token) do
    url = "#{@fcm_base_url}/projects/#{project_id}/messages:send"

    payload = %{message: Message.to_map(message)}

    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: payload, headers: headers) do
      {:ok, %{status: 200, body: %{"name" => message_id}}} ->
        {:ok, message_id}

      {:ok, %{status: status, body: body}} ->
        error = parse_fcm_error(body)
        Logger.error("FCM send failed: #{status} - #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.error("FCM request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_multicast(tokens, message, project_id, access_token) do
    # Remove tokens from the base message
    base_message = Map.delete(message, :tokens)

    # Create individual messages for each token
    messages =
      Enum.map(tokens, fn token ->
        Map.put(base_message, :token, token)
      end)

    # Send messages concurrently with limited concurrency
    responses =
      messages
      |> Task.async_stream(
        fn msg -> send_message(msg, project_id, access_token) end,
        max_concurrency: @max_concurrent_requests,
        timeout: 30_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_exit, reason}}
      end)

    # Calculate statistics
    success_count =
      Enum.count(responses, fn
        {:ok, _} -> true
        _ -> false
      end)

    failure_count = length(responses) - success_count

    result = %{
      success_count: success_count,
      failure_count: failure_count,
      responses: responses
    }

    Logger.info("Multicast complete: #{success_count} succeeded, #{failure_count} failed")
    {:ok, result}
  end

  # defp add_webpush_config(payload, %{webpush: webpush}) when is_map(webpush) do
  #   Map.put(payload, :webpush, webpush)
  # end

  # defp add_webpush_config(payload, _), do: payload

  defp parse_fcm_error(%{"error" => %{"message" => message, "details" => details}}) do
    %{message: message, details: details}
  end

  defp parse_fcm_error(%{"error" => %{"message" => message}}) do
    message
  end

  defp parse_fcm_error(%{"error" => error}) when is_binary(error) do
    error
  end

  defp parse_fcm_error(body), do: body
end
