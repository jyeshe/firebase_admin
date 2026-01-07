# Firebase Integration Tests

This document describes how to set up and run integration tests that interact with real Firebase services.

## Prerequisites

1. **Service Account Key**: Set via environment variable (see setup below)
2. **FCM Sender ID**: Firebase FCM Sender ID

## Setup

### 1. Service Account Key File

You need a Firebase service account key JSON file. Place it in the project root as `firebase-sa-test.json`:

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project 
3. Go to Project Settings > Service Accounts
4. Click "Generate New Private Key"
5. Save the downloaded file as `firebase-sa-test.json` in the project root

## Running Integration Tests

### Run All Integration Tests
```bash
MIX_ENV=integration_test mix test test/integration/ --include integration
```

### Run Specific Integration Test Suites
```bash
MIX_ENV=integration_test mix test test/integration/<<filename>>.exs --include integration
```

## Test Structure

### Integration Test Helper
- `test/integration_test_helper.exs`: Provides utilities for integration tests
- Validates environment configuration
- Provides test data generators
- Handles test cleanup

### Test Categories

#### Authentication Tests (`firebase_admin_auth_integration_test.exs`)
- User creation and management
- Custom token generation
- User lookup by email/phone
- User deletion and cleanup

#### Messaging Tests (`firebase_admin_messaging_integration_test.exs`)
- Single device messaging
- Topic messaging
- Multicast messaging
- Topic subscription/unsubscription
- Message validation

#### Token Verifier Tests (`firebase_admin_token_verifier_integration_test.exs`)
- Public key fetching from Google
- Token validation (format, issuer, audience, expiration)
- Key caching and TTL
- Custom token structure validation

## Important Notes

### Rate Limiting
- Firebase APIs have rate limits
- Tests include rate limit handling
- Some test failures are expected with test tokens

### Test Data Cleanup
- Tests create real Firebase users for testing
- Cleanup is performed automatically
- Failed tests may leave test data (manual cleanup may be needed)

### Security
- Never commit service account keys to version control
- Add `firebase-sa-test.json` to `.gitignore`
- Test tokens are not real device tokens

### Test Tokens
- FCM tests use generated test tokens
- These tokens won't deliver to real devices
- Some messaging tests expect "invalid token" errors

## Troubleshooting

### Missing Service Account File
```
Error: Integration tests require firebase-sa-test.json file in project root
```
Solution: Place your Firebase service account JSON file as `firebase-sa-test.json` in the project root.

### Invalid JSON
```
Error: Invalid JSON in firebase-sa-test.json
```
Solution: Ensure the JSON file is properly formatted.

### Permission Errors
```
Error: Permission denied
```
Solution: Ensure the service account has the necessary permissions:
- Firebase Authentication Admin
- Firebase Cloud Messaging Admin
- Service Account Token Creator

### Network Errors
```
Error: Connection failed
```
Solution: Check internet connectivity and Firebase service status.

## Example Service Account Permissions

Your service account should have these roles:
- `Firebase Authentication Admin`
- `Firebase Cloud Messaging Admin`
- `Service Account Token Creator`

## Continuous Integration

For CI environments, you'll need to create the service account file from a secret:

### GitHub Actions
```yaml
steps:
  - name: Create service account file
    run: echo '${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}' > firebase-sa-test.json
  - name: Run integration tests
    run: ./scripts/run_integration_tests.sh all
```

### GitLab CI
```yaml
before_script:
  - echo "$FIREBASE_SERVICE_ACCOUNT_JSON" > firebase-sa-test.json
script:
  - ./scripts/run_integration_tests.sh all
```

### Jenkins
```groovy
pipeline {
  stages {
    stage('Setup') {
      steps {
        writeFile file: 'firebase-sa-test.json', text: env.FIREBASE_SERVICE_ACCOUNT_JSON
      }
    }
    stage('Test') {
      steps {
        sh './scripts/run_integration_tests.sh all'
      }
    }
  }
}
```