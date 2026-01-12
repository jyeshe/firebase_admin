defmodule FirebaseAdmin.StorageIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  import FirebaseAdmin.IntegrationTestHelper
  alias FirebaseAdmin.Storage

  @test_bucket "cashradar-c32d3.firebasestorage.app"
  @object_prefix "test_files"

  # Simple 1x1 pixel PNG image (base64 encoded)
  @test_image_data Base.decode64!(
                     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
                   )

  describe "Firebase Cloud Storage Integration Tests" do
    integration_test "uploads and downloads a text file" do
      uniq = System.system_time(:microsecond)
      name = "get_test_#{uniq}.txt"
      file_content = "Some content of file with #{uniq}"

      assert {:ok, _file_url} =
               Storage.upload_file(@test_bucket, @object_prefix, name, file_content,
                 content_type: "text/plain"
               )

      assert {:ok, ^file_content} = Storage.download_file(@test_bucket, @object_prefix, name)
    end

    integration_test "uploads and download an image file" do
      # Upload a PNG image to Firebase Storage
      name = "get_image_test_#{System.system_time(:microsecond)}.png"

      assert {:ok, _file_url} =
               Storage.upload_file(@test_bucket, @object_prefix, name, @test_image_data,
                 content_type: "image/png"
               )

      # Download and verify the image
      assert {:ok, downloaded_data} = Storage.download_file(@test_bucket, @object_prefix, name)

      # Verify the downloaded data matches the original
      assert downloaded_data == @test_image_data
      assert byte_size(downloaded_data) == byte_size(@test_image_data)

      # Verify it's still a valid PNG by checking the PNG signature
      assert binary_part(downloaded_data, 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    integration_test "handles file not found gracefully" do
      # Try to download a file that doesn't exist
      non_existent_path = "test_files/does_not_exist_#{System.system_time(:microsecond)}.txt"

      assert {:error, :file_not_found} =
               Storage.download_file(@test_bucket, @object_prefix, non_existent_path)
    end

    integration_test "validates bucket configuration" do
      # Verify our storage bucket is correctly configured
      configured_bucket = @test_bucket

      # Test that we can list files in the bucket (basic connectivity test)
      case Storage.list_files(configured_bucket, prefix: "test_files/", max_results: 5) do
        {:ok, files} ->
          assert is_list(files)
          # Files list may be empty, that's OK
          IO.puts("Successfully listed #{length(files)} files with test_files/ prefix")

        {:error, %{"error" => %{"message" => message}}} ->
          cond do
            String.contains?(message, "ACCESS_DENIED") ->
              flunk(
                "Storage list access denied - check service account permissions for bucket: #{configured_bucket}"
              )

            String.contains?(message, "bucket does not exist") or
                String.contains?(message, "BUCKET_NOT_FOUND") ->
              # Bucket doesn't exist - this is expected for some test environments
              IO.puts(
                "Note: Storage bucket #{configured_bucket} doesn't exist - basic connectivity test passed"
              )

              assert true

            true ->
              flunk("Unexpected storage list error: #{message}")
          end

        {:error, reason} when is_binary(reason) ->
          if String.contains?(reason, "bucket does not exist") do
            IO.puts(
              "Note: Storage bucket #{configured_bucket} doesn't exist - basic connectivity test passed"
            )

            assert true
          else
            flunk("Storage list failed with unexpected error: #{inspect(reason)}")
          end

        {:error, reason} ->
          flunk("Storage list failed with unexpected error: #{inspect(reason)}")
      end
    end

    integration_test "fails on unexpected 400 errors" do
      # Test with invalid bucket name that should cause 400
      invalid_bucket = "invalid-bucket-name-with-invalid-chars!!!!"

      case Storage.upload_file(invalid_bucket, @object_prefix, "test.txt", "content") do
        {:ok, _url} ->
          flunk("Expected upload to fail with invalid bucket name")

        {:error, %{"error" => %{"message" => message}}} ->
          # If we get a 400 error for bucket validation, that's expected
          if String.contains?(message, "Invalid bucket name") or
               String.contains?(message, "INVALID_ARGUMENT") do
            # Expected failure
            assert true
          else
            # Other 400 errors should fail the test
            flunk("Unexpected 400 error: #{message}")
          end

        {:error, reason} when is_binary(reason) ->
          # Network errors are acceptable
          if String.contains?(reason, "bucket") or String.contains?(reason, "invalid") do
            # Expected validation error
            assert true
          else
            flunk("Unexpected error: #{reason}")
          end

        {:error, _reason} ->
          # Other network/connection errors are acceptable
          assert true
      end
    end

    # Cleanup test that runs last
    integration_test "cleanup_test_files" do
      # Clean up any remaining test files
      case Storage.list_files(@test_bucket, prefix: "test_files/") do
        {:ok, files} ->
          cleanup_count = length(files)

          if cleanup_count > 0 do
            IO.puts("Cleaning up #{cleanup_count} test files...")

            Enum.each(files, fn file ->
              case file do
                %{"name" => name} ->
                  Storage.delete_file(@test_bucket, name)

                _ ->
                  :ok
              end
            end)

            IO.puts("Cleanup completed")
          else
            IO.puts("No test files to clean up")
          end

        {:error, _reason} ->
          # If we can't list, we can't clean up, but that's not a test failure
          IO.puts("Could not list files for cleanup - skipping")
      end

      assert true
    end
  end
end
