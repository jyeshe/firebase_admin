# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2024-01-XX

### Added
- Initial release of Firebase Admin SDK for Elixir
- ID Token Verification using Joken
- Public key caching with DETS
- Automatic key refresh every hour
- Refresh Token Revocation
- Firebase Cloud Messaging (FCM)
  - Single device messaging
  - Multicast messaging with concurrent sends
  - Android, iOS, and Web push configurations
  - Automatic rate limiting
- Cloud Storage operations
  - File upload with metadata
  - File download
  - File deletion
  - Signed URL generation
  - File listing with prefix filtering
- Comprehensive error handling
- Full documentation and examples
- Test suite with mocked HTTP requests

### Architecture
- GenServerless token verifier with automatic key refresh
- DETS persistent caching for Google public keys
- Concurrent FCM multicast using Task.async_stream
- Goth integration for Google OAuth2
- Req HTTP client for all API calls

### Dependencies
- joken ~> 2.6 (JWT handling)
- goth ~> 1.4 (Google OAuth)
- req ~> 0.4 (HTTP client)
- jason ~> 1.4 (JSON encoding/decoding)

[unreleased]: https://github.com/yourusername/firebase_admin/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/firebase_admin/releases/tag/v0.1.0
