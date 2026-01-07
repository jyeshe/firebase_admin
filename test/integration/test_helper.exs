# Load main test helper first
Code.require_file("../test_helper.exs", __DIR__)

# Load integration test helper
Code.require_file("../integration_test_helper.exs", __DIR__)

# Start ExUnit if not already started
ExUnit.start()
