defmodule FirebaseAdmin.TokenVerifier do
  @moduledoc """
  Verifies Firebase ID tokens using Joken.

  This module fetches Google's public keys, caches them using :dets,
  and verifies JWT tokens issued by Firebase Authentication.
  """

  require Logger

  alias FirebaseAdmin.Auth

  @google_certs_url "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
  @dets_table_name :firebase_public_keys
  @cache_ttl 3600
  @max_token_length 2500
  @max_fetch_retries Application.compile_env(:firebase_admin, :max_fetch_retries) || 10
  @refresh_check_interval :timer.seconds(10)

  @doc """
  Initializes the cache persistence if needed
  """
  def ensure_initialized do
    with :undefined <- :dets.info(@dets_table_name, :filename) do
      init_cache()
    end

    :ok
  end

  @doc """
  Verifies a Firebase ID token.

  ## Parameters

    - `token` - The Firebase ID token string

  ## Returns

    - `{:ok, claims}` - Token is valid, returns decoded claims
    - `{:error, reason}` - Token is invalid or verification failed

  ## Claims validation

  The token is verified for:
  - Valid signature using Google's public keys
  - Token not expired
  - Issued by Firebase Authentication
  - Audience matches the project ID
  - Subject (user ID) is present
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def verify(token) when is_binary(token) do
    # Lazy initialization
    with :ok <- ensure_initialized(),
      :ok <- basic_token_validation(token),
      {:ok, keys} <- load_keys_from_cache() do
        with :error <- do_verify(token, keys) do
          maybe_refresh_keys()
        end
    end
  end

  @doc """
  Forces a refresh of the cached public keys.
  """
  @spec refresh_keys() :: :ok
  def refresh_keys do
    task = Task.async(fn ->
      schedule_refresh()
      fetch_and_cache_keys()
    end)

    Task.yield(task, 5000) || Task.ignore(task)

    :ok
  end

  @doc """
  Checks if keys should be refreshed and refreshes them if necessary.
  Called periodically by the timer.
  """
  def maybe_refresh_keys do
    case should_fetch_keys?() do
      true -> refresh_keys()
      false -> :ok
    end
  end

  defp basic_token_validation(token) when byte_size(token) > @max_token_length do
    {:error, :invalid_token_length}
  end

  defp basic_token_validation(token) do
    case String.split(token, ".") do
      [_, _, _] -> :ok
      _ -> {:error, :invalid_token_format}
    end
  end

  defp init_cache do
    # Open or create DETS table
    dets_path = dets_file_path()
    File.mkdir_p!(Path.dirname(dets_path))

    {:ok, _ref} =
      :dets.open_file(@dets_table_name,
        file: String.to_charlist(dets_path),
        type: :set
      )

     maybe_refresh_keys()
  end

  defp fetch_and_cache_keys do
    case fetch_public_keys() do
      {:ok, keys} ->
        cache_keys(keys)
        Logger.info("Fetched and cached #{map_size(keys)} Firebase public keys")

      {:error, reason} ->
        Logger.error("Failed to fetch public keys: #{inspect(reason)}")
    end
  end

  defp should_fetch_keys? do
    case :dets.lookup(@dets_table_name, :keys) do
      [{:keys, keys, timestamp}] when is_map(keys) ->
        last_fetch = DateTime.from_unix!(timestamp)
        map_size(keys) == 0 or DateTime.diff(DateTime.utc_now(), last_fetch) > @cache_ttl

      _ ->
        # No cached keys or invalid cache entry
        true
    end
  end

  defp do_verify(token, keys) when is_map(keys) and map_size(keys) > 0 do
    with {:ok, header} <- peek_header(token),
         {:ok, kid} <- get_kid(header),
         {:ok, public_key} <- get_public_key(keys, kid),
         {:ok, project_id} <- Auth.get_project_id(),
         {:ok, claims} <- verify_token_with_key(token, public_key, project_id) do
      validate_claims(claims, project_id)
    end
  end

  defp do_verify(_token, _keys) do
    {:error, :no_public_keys_available}
  end

  defp peek_header(token) do
    case String.split(token, ".") do
      [header_b64, _, _] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, header} -> {:ok, header}
              _ -> {:error, :invalid_token_header}
            end

          _ ->
            {:error, :invalid_token_encoding}
        end

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp get_kid(%{"kid" => kid}), do: {:ok, kid}
  defp get_kid(_), do: {:error, :no_kid_in_header}

  defp get_public_key(keys, kid) do
    case Map.get(keys, kid) do
      nil -> {:error, :key_not_found}
      key -> {:ok, key}
    end
  end

  defp verify_token_with_key(token, public_key, project_id) do
    signer = Joken.Signer.create("RS256", %{"pem" => public_key})

    with {:ok, claims} <- Joken.verify(token, signer) do
      case validate_claims(claims, project_id) do
        {:ok, _} -> {:ok, claims}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_claims(claims, project_id) do
    with :ok <- validate_expiration(claims),
         :ok <- validate_issued_at(claims),
         :ok <- validate_issuer(claims, project_id),
         :ok <- validate_audience(claims, project_id),
         :ok <- validate_subject(claims) do
      {:ok, claims}
    end
  end

  defp validate_expiration(%{"exp" => exp}) do
    now = System.system_time(:second)

    if exp > now do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp validate_expiration(_), do: {:error, :missing_exp_claim}

  defp validate_issued_at(%{"iat" => iat}) do
    now = System.system_time(:second)
    # Token can't be issued in the future (with 5 minute tolerance for clock skew)
    if iat <= now + 300 do
      :ok
    else
      {:error, :token_issued_in_future}
    end
  end

  defp validate_issued_at(_), do: {:error, :missing_iat_claim}

  defp validate_issuer(%{"iss" => issuer}, project_id) do
    expected_issuer = "https://securetoken.google.com/#{project_id}"

    if issuer == expected_issuer do
      :ok
    else
      {:error, :invalid_issuer}
    end
  end

  defp validate_issuer(_, _), do: {:error, :missing_iss_claim}

  defp validate_audience(%{"aud" => audience}, project_id) do
    if audience == project_id do
      :ok
    else
      {:error, :invalid_audience}
    end
  end

  defp validate_audience(_, _), do: {:error, :missing_aud_claim}

  defp validate_subject(%{"sub" => sub}) when is_binary(sub) and byte_size(sub) > 0 do
    if String.length(sub) <= 128 do
      :ok
    else
      {:error, :invalid_subject}
    end
  end

  defp validate_subject(_), do: {:error, :missing_or_invalid_sub_claim}

  defp fetch_public_keys do
    case Req.get(@google_certs_url, max_retries: @max_fetch_retries) do
      {:ok, %{status: 200, body: body}} ->
        parse_keys(body)

      {:ok, %{status: status}} ->
        schedule_refresh()
        {:error, {:http_error, status}}

      {:error, reason} ->
        schedule_refresh()
        {:error, reason}
    end
  end

  defp parse_keys(body) when is_map(body) do
    # Response is already parsed JSON
    {:ok, body}
  end

  defp parse_keys(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, keys} -> {:ok, keys}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp cache_keys(keys) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    :dets.insert(@dets_table_name, {:keys, keys, timestamp})
    :dets.sync(@dets_table_name)
  end

  defp load_keys_from_cache do
    case :dets.lookup(@dets_table_name, :keys) do
      [{:keys, keys, _timestamp}] -> {:ok, keys}
      [] -> {:error, :no_cached_keys}
    end
  end

  defp schedule_refresh do
    # Schedule new timer and store the reference
    {:ok, timer_ref} = :timer.apply_after(@refresh_check_interval, __MODULE__, :refresh_keys, [])
    :persistent_term.put({__MODULE__, :timer_ref}, timer_ref)

    :ok
  end

  defp dets_file_path do
    base_path = Application.get_env(:firebase_admin, :cache_dir, "priv/cache")
    Path.join([base_path, "firebase_public_keys.dets"])
  end
end
