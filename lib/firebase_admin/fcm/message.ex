defmodule FirebaseAdmin.FCM.Message do
  @moduledoc """
  Structured FCM message:

      %{
        token: "some-device-token"
        notification: %{
          title: "Title",
          body: "Body",
          image: "https://..."
        },
        data: %{
          "key1" => "value1",
          "key2" => "value2"
        },
        android: %{
          priority: "high",
          notification: %{
            sound: "default",
            color: "#ff0000"
          }
        },
        apns: %{
          payload: %{
            aps: %{
              sound: "default",
              badge: 1
            }
          }
        },
        webpush: %{ # Optional Web config
          notification: %{
            icon: "https://..."
          }
        }
      }
  """

  defstruct [:token, :tokens, :topic, :condition, :notification, :data, :android, :apns]

  defmodule Notification do
    @moduledoc false
    defstruct [:title, :body, :image]

    def to_map(struct) when is_struct(struct, __MODULE__) do
      with %{image: nil} = map <- Map.from_struct(struct) do
        Map.delete(map, :image)
      end
    end
  end

  @doc """
  Build a message for a topic


  """
  def build_for_topic(topic, notification, data \\ %{}, opts \\ []) when is_binary(topic) do
    build(notification, data, opts)
    |> Map.put(:topic, topic)
  end

  def build_for_device(device_token, notification, data \\ %{}, opts \\ [])
      when is_binary(device_token) do
    build(notification, data, opts)
    |> Map.put(:token, device_token)
  end

  def build_for_multicast(device_tokens, notification, data \\ %{}, opts \\ [])
      when is_list(device_tokens) do
    build(notification, data, opts)
    |> Map.put(:tokens, device_tokens)
  end

  def build_for_condition(condition, notification, data \\ %{}, opts \\ [])
      when is_binary(condition) do
    build(notification, data, opts)
    |> Map.put(:condition, condition)
  end

  def to_map(message) when is_struct(message, __MODULE__) do
    Map.from_struct(message)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp build(notification, data, opts) when is_map(data) do
    string_data =
      data
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Map.new()

    %__MODULE__{
      notification: Notification.to_map(struct(Notification, notification)),
      data: string_data,
      android: Keyword.get(opts, :android),
      apns: Keyword.get(opts, :apns)
    }
  end
end
