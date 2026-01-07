#!/bin/bash

# Firebase Admin Elixir - Integration Test Runner
# This script helps you run integration tests with proper configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} Firebase Admin Integration Tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

check_environment() {
    echo -e "${BLUE}Checking environment...${NC}"
    
    if [ ! -f "firebase-sa-test.json" ]; then
        echo -e "${RED}Error: firebase-sa-test.json file not found in project root${NC}"
        echo -e "${YELLOW}Please place your Firebase service account JSON file as:${NC}"
        echo ""
        echo "firebase-sa-test.json"
        echo ""
        echo -e "${YELLOW}You can get this file from:${NC}"
        echo "Firebase Console > Project Settings > Service Accounts > Generate New Private Key"
        echo ""
        exit 1
    fi

    # Validate JSON format
    jq empty firebase-sa-test.json > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: firebase-sa-test.json contains invalid JSON${NC}"
        exit 1
    fi

    # Check if project ID matches
    JSON_PROJECT_ID=$(jq -r '.project_id' firebase-sa-test.json)
    if [ "$JSON_PROJECT_ID" != "$PROJECT_ID" ]; then
        echo -e "${YELLOW}Warning: Service account project ID ($JSON_PROJECT_ID) doesn't match expected project ID ($PROJECT_ID)${NC}"
    fi

    echo -e "${GREEN}✓ Environment looks good${NC}"
    echo ""
}

check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Install it with: brew install jq"
        exit 1
    fi

    # Check if mix is available
    if ! command -v mix &> /dev/null; then
        echo -e "${RED}Error: Elixir/Mix is required but not available${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Dependencies are available${NC}"
    echo ""
}

run_tests() {
    local test_filter="$1"
    local test_path="$2"
    
    echo -e "${BLUE}Running integration tests...${NC}"
    echo -e "Test filter: ${YELLOW}$test_filter${NC}"
    echo -e "Test path: ${YELLOW}$test_path${NC}"
    echo ""
    
    # Compile first
    echo -e "${BLUE}Compiling...${NC}"
    MIX_ENV=integration_test mix compile
    
    # Run tests
    echo -e "${BLUE}Executing tests...${NC}"
    MIX_ENV=integration_test mix test "$test_path" --include integration --timeout 120000
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Integration tests completed successfully${NC}"
    else
        echo ""
        echo -e "${RED}✗ Some integration tests failed${NC}"
        exit 1
    fi
}

show_help() {
    echo "Firebase Admin Integration Test Runner"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all                    Run all integration tests"
    echo "  auth                   Run authentication integration tests"
    echo "  messaging              Run messaging integration tests"
    echo "  token-verifier         Run token verifier integration tests"
    echo "  help                   Show this help message"
    echo ""
    echo "Required Files:"
    echo "  firebase-sa-test.json           Firebase service account JSON file (required)"
    echo ""
    echo "Examples:"
    echo "  ./scripts/run_integration_tests.sh all"
    echo "  ./scripts/run_integration_tests.sh auth"
    echo "  ./scripts/run_integration_tests.sh messaging"
    echo ""
}

# Main script
case "${1:-all}" in
    "all")
        print_header
        check_dependencies
        check_environment
        run_tests "all integration tests" "test/integration/"
        ;;
    
    "auth")
        print_header
        check_dependencies
        check_environment
        run_tests "authentication tests" "test/integration/auth_integration_test.exs"
        ;;
    
    "messaging")
        print_header
        check_dependencies
        check_environment
        run_tests "messaging tests" "test/integration/messaging_integration_test.exs"
        ;;
    
    "token-verifier")
        print_header
        check_dependencies
        check_environment
        run_tests "token verifier tests" "test/integration/token_verifier_integration_test.exs"
        ;;

    "storage")
        print_header
        check_dependencies
        check_environment
        run_tests "token verifier tests" "test/integration/storage_integration_test.exs"
        ;;
    
    "help"|"-h"|"--help")
        show_help
        ;;
    
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac