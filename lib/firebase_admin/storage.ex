defmodule FirebaseAdmin.Storage do
  @moduledoc """
  Firebase Cloud Storage implementation.

  Provides functionality to interact with Google Cloud Storage for Firebase,
  including file upload, download, deletion, and signed URL generation.
  """

  require Logger
  alias FirebaseAdmin.Auth

  @storage_base_url "https://storage.googleapis.com"
  @storage_api_url "https://storage.googleapis.com/storage/v1"

  @doc """
  Uploads a file to Firebase Cloud Storage.

  ## Parameters

    - `bucket` - The storage bucket name (without gs:// prefix)
    - `path` - The destination path in the bucket
    - `file_content` - The file content as binary
    - `opts` - Optional parameters:
      - `:content_type` - MIME type (default: "application/octet-stream")
      - `:metadata` - Custom metadata map

  ## Returns

    - `{:ok, url}` - File uploaded successfully with public URL
    - `{:error, reason}` - Upload failed

  ## Examples

      iex> content = File.read!("photo.jpg")
      iex> FirebaseAdmin.Storage.upload_file("my-bucket", "images/photo.jpg", content,
      ...>   content_type: "image/jpeg")
      {:ok, "https://storage.googleapis.com/my-bucket/images/photo.jpg"}
  """
  @spec upload_file(String.t(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def upload_file(bucket, prefix, name, file_content, opts \\ []) when is_binary(file_content) do
    with {:ok, access_token} <- Auth.get_access_token() do
      do_upload(bucket, path(prefix, name), file_content, opts, access_token)
    end
  end

  @doc """
  Downloads a file from Firebase Cloud Storage.

  ## Parameters

    - `bucket` - The storage bucket name
    - `prefix` - The folder in the bucket
    - `name` - The file name in the bucket

  ## Returns

    - `{:ok, content}` - File content as binary
    - `{:error, reason}` - Download failed

  ## Examples

      iex> FirebaseAdmin.Storage.download_file("my-bucket", "some-id", "images/photo.jpg")
      {:ok, <<binary_content>>}
  """
  @spec download_file(String.t(), String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def download_file(bucket, prefix, name) do
    with {:ok, access_token} <- Auth.get_access_token() do
      do_download(bucket, path(prefix, name), access_token)
    end
  end

  @doc """
  Deletes a file from Firebase Cloud Storage.

  ## Parameters

    - `bucket` - The storage bucket name
    - `path` - The file path in the bucket

  ## Returns

    - `:ok` - File deleted successfully
    - `{:error, reason}` - Deletion failed

  ## Examples

      iex> FirebaseAdmin.Storage.delete_file("my-bucket", "images/photo.jpg")
      :ok
  """
  @spec delete_file(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_file(bucket, path) do
    with {:ok, access_token} <- Auth.get_access_token() do
      do_delete(bucket, path, access_token)
    end
  end

  @doc """
  Generates a signed URL for temporary access to a file.

  ## Parameters

    - `bucket` - The storage bucket name
    - `path` - The file path in the bucket
    - `expires_in` - Expiration time in seconds (default: 3600)

  ## Returns

    - `{:ok, url}` - Signed URL
    - `{:error, reason}` - Failed to generate URL

  ## Examples

      iex> FirebaseAdmin.Storage.get_signed_url("my-bucket", "images/photo.jpg", 7200)
      {:ok, "https://storage.googleapis.com/my-bucket/images/photo.jpg?X-Goog-Algorithm=..."}
  """
  @spec get_signed_url(String.t(), String.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def get_signed_url(bucket, path, expires_in \\ 3600) do
    with {:ok, email} <- Auth.get_service_account_email(),
         {:ok, private_key} <- Auth.get_private_key() do
      do_sign_url(bucket, path, expires_in, email, private_key)
    end
  end

  @doc """
  Lists files in a bucket with optional prefix filtering.

  ## Parameters

    - `bucket` - The storage bucket name
    - `opts` - Optional parameters:
      - `:prefix` - Only return files with this prefix
      - `:max_results` - Maximum number of results (default: 1000)

  ## Returns

    - `{:ok, files}` - List of file metadata maps
    - `{:error, reason}` - List failed

  ## Examples

      iex> FirebaseAdmin.Storage.list_files("my-bucket", prefix: "images/")
      {:ok, [%{"name" => "images/photo1.jpg", "size" => "12345", ...}, ...]}
  """
  @spec list_files(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_files(bucket, opts \\ []) do
    with {:ok, access_token} <- Auth.get_access_token() do
      do_list(bucket, opts, access_token)
    end
  end

  # Private functions

  defp do_upload(bucket, path, file_content, opts, access_token) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    metadata = Keyword.get(opts, :metadata, %{})

    url =
      "#{@storage_base_url}/upload/storage/v1/b/#{bucket}/o?uploadType=media&name=#{path}"

    headers = [
      {"authorization", "Bearer #{access_token}"},
      {"content-type", content_type}
    ]

    # Add custom metadata headers
    headers = add_metadata_headers(headers, metadata)

    case Req.post(url, body: file_content, headers: headers) do
      {:ok, %{status: 200, body: _response}} ->
        file_url = build_file_url(bucket, path)

        Logger.info("Successfully uploaded file to #{file_url}")
        {:ok, file_url}

      {:ok, %{status: status, body: body}} ->
        error = parse_storage_error(body)
        Logger.error("Storage upload failed: #{status} - #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.error("Storage upload request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_download(bucket, path, access_token) do
    query_params = [{"alt", "media"}]
    query_string = URI.encode_query(query_params)
    url = "#{@storage_api_url}/b/#{bucket}/o/#{path}?#{query_string}"

    headers = [
      {"authorization", "Bearer #{access_token}"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        {:ok, resp_body}

      {:ok, %{status: 404}} ->
        {:error, :file_not_found}

      {:ok, %{status: status, body: resp_body}} ->
        error = parse_storage_error(resp_body)
        Logger.error("Storage download failed: #{status} - #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.error("Storage download request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_delete(bucket, path, access_token) do
    encoded_path = URI.encode(path)
    url = "#{@storage_api_url}/b/#{bucket}/o/#{encoded_path}"

    headers = [
      {"authorization", "Bearer #{access_token}"}
    ]

    case Req.delete(url, headers: headers) do
      {:ok, %{status: 204}} ->
        Logger.info("Successfully deleted file: #{bucket}/#{path}")
        :ok

      {:ok, %{status: 404}} ->
        {:error, :file_not_found}

      {:ok, %{status: status, body: body}} ->
        error = parse_storage_error(body)
        Logger.error("Storage delete failed: #{status} - #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.error("Storage delete request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_list(bucket, opts, access_token) do
    prefix = Keyword.get(opts, :prefix)
    max_results = Keyword.get(opts, :max_results, 1000)

    query_params = [
      {"maxResults", max_results}
    ]

    query_params = if prefix, do: [{"prefix", prefix} | query_params], else: query_params
    query_string = URI.encode_query(query_params)

    url = "#{@storage_api_url}/b/#{bucket}/o?#{query_string}"

    headers = [
      {"authorization", "Bearer #{access_token}"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        {:ok, items}

      {:ok, %{status: 200, body: %{}}} ->
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        error = parse_storage_error(body)
        Logger.error("Storage list failed: #{status} - #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.error("Storage list request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_sign_url(bucket, path, expires_in, email, private_key) do
    expiration = System.system_time(:second) + expires_in

    resource = "/#{bucket}/#{path}"

    string_to_sign = build_string_to_sign("GET", resource, expiration)

    case sign_string(string_to_sign, private_key) do
      {:ok, signature} ->
        query_params = [
          {"GoogleAccessId", email},
          {"Expires", expiration},
          {"Signature", signature}
        ]

        query_string = URI.encode_query(query_params)
        url = "#{@storage_base_url}#{resource}?#{query_string}"

        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_string_to_sign(method, resource, expiration) do
    """
    #{method}


    #{expiration}
    #{resource}
    """
    |> String.trim()
  end

  defp sign_string(string, private_key_pem) do
    try do
      [pem_entry] = :public_key.pem_decode(private_key_pem)
      private_key = :public_key.pem_entry_decode(pem_entry)

      signature = :public_key.sign(string, :sha256, private_key)
      encoded_signature = Base.encode64(signature)

      {:ok, encoded_signature}
    rescue
      error ->
        Logger.error("Failed to sign URL: #{inspect(error)}")
        {:error, :signing_failed}
    end
  end

  defp add_metadata_headers(headers, metadata) when map_size(metadata) == 0 do
    headers
  end

  defp add_metadata_headers(headers, metadata) do
    metadata_headers =
      Enum.map(metadata, fn {key, value} ->
        {"x-goog-meta-#{key}", to_string(value)}
      end)

    headers ++ metadata_headers
  end

  defp build_file_url(bucket, path) do
    "#{@storage_base_url}/#{bucket}/#{path}"
  end

  defp parse_storage_error(%{"error" => %{"message" => message}}) do
    message
  end

  defp parse_storage_error(%{"error" => error}) when is_binary(error) do
    error
  end

  defp parse_storage_error(body), do: body

  defp path(prefix, name), do: URI.encode("#{prefix}/#{name}", &URI.char_unreserved?/1)
end
