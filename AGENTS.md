# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project Overview

Kadb is a pure Dart implementation of the ADB (Android Debug Bridge) protocol that enables connecting to Android devices without requiring the ADB server. The project includes both Dart and Kotlin implementations, with the Dart version being the primary focus in the root directory.

## Build/Test Commands

### Dart Package (Root Directory)
```bash
# Get dependencies
dart pub get

# Run tests (Note: No test files currently exist in test/ directory)
dart test

# Analyze code
dart analyze

# Run examples
dart run example-dartonly/scrcpy_server.dart
dart run example-dartonly/device_info_example.dart
```

### Kotlin Multiplatform (kadb-kt-deprecated/ directory)
```bash
# Build all targets
./kadb-kt-deprecated/gradlew build

# Run tests
./kadb-kt-deprecated/gradlew test

# Run test application
./kadb-kt-deprecated/gradlew :kadb-test-app:run
```

## Critical Architecture Patterns

### Connection Management
- **AdbConnection** in [`lib/core/adb_connection.dart`](lib/core/adb_connection.dart:17) manages the entire ADB protocol lifecycle
- Connection payload format is critical: `'host::用户@主机名\u0000'` (25 bytes total) - see line 62 in adb_connection.dart
- Authentication follows a two-step process: signature first, then RSA public key if signature fails

### Stream Architecture
- All operations use stream-based communication via **AdbStream** classes
- **AdbShellStream** for shell commands, **AdbSyncStream** for file operations
- Streams are automatically cleaned up when closed (see line 267-272 in adb_connection.dart)

### Protocol Implementation
- ADB protocol constants defined in [`lib/core/adb_protocol.dart`](lib/core/adb_protocol.dart:3)
- Message structure follows AOSP specification exactly (see protocol.txt reference in comments)
- Little-endian byte order is mandatory for all protocol communications

## Code Style Guidelines

### Dart Implementation
- Uses standard Dart lints via `package:lints/recommended.yaml`
- Chinese comments throughout the codebase (maintain consistency)
- API design mirrors the Kotlin version for consistency
- Deprecated methods kept for backward compatibility (see [`KadbDart.connect()`](lib/kadb_dart.dart:81))

### Key Naming Conventions
- ADB protocol constants: `CMD_*`, `authType*`
- Private methods prefixed with underscore
- Stream classes suffixed with `Stream`
- Connection context classes suffixed with `Ctx`

## Critical Implementation Details

### Certificate Management
- **CertUtils.loadKeyPair()** automatically generates key pairs if none exist
- Authentication uses both signature and RSA public key methods
- System identity generation is crucial for successful connections

### File Operations
- APK installation has two paths: `cmd package install` (modern) vs `pm install` (legacy)
- File permissions use decimal format (e.g., 420 for 0o644)
- Split APK installation requires session management with proper cleanup

### Error Handling
- Connection failures fall back through authentication methods automatically
- Stream close operations are wrapped in try-catch to prevent cascading failures
- TLS upgrade is not implemented and will throw `UnsupportedError`

## Testing Considerations
- **No test files exist** - the `test/` directory is empty
- Manual testing via example scripts in `example-dartonly/`
- Kotlin version has comprehensive test suite in `kadb-kt-deprecated/`

## Performance Notes
- Debug mode significantly impacts performance - disable for production
- TCP forwarders should have debug disabled for optimal performance
- Connection pooling is not implemented - each operation creates new connections

## Common Pitfalls
1. **Payload format**: Must use exact system identity format or authentication fails
2. **File permissions**: Use decimal, not octal format for mode parameters
3. **Stream cleanup**: Always close streams to prevent resource leaks
4. **Connection timeout**: Default 30s may be insufficient for slow devices
5. **APK installation**: Check device features before choosing install method