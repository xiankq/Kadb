# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kadb is a library that enables connecting to Android devices without requiring the ADB server. Originally a Kotlin Multiplatform library (now deleted), the project now focuses on the Dart implementation (`kadb_dart`). It supports wireless debugging, APK installation, file management, port forwarding, and shell command execution. The primary codebase is the Dart implementation in `lib/`, with a complete Flutter scrcpy example application in `example/`.

## Repository Structure

- `kadb-kt/` - Main Kotlin Multiplatform library (DELETED - now only Dart implementation)
- `lib/` - Dart implementation of the ADB protocol (primary codebase)
  - Core implementation in `lib/kadb_dart.dart` and supporting modules
- `example/` - Flutter scrcpy application demonstrating kadb_dart usage
  - Complete Flutter app with Android/iOS support
  - Uses fvp and video_player for video playback
  - Includes local kadb_dart dependency
- `example-dartonly/` - Pure Dart example files (moved from root example/)
- `test/` - Dart test files for the kadb_dart package
- `adbDocumentation/` - ADB protocol documentation
- `assets/scrcpy-server` - Scrcpy server binary

## Build Commands

### Dart Package (Primary Implementation)
```bash
# Get dependencies
dart pub get

# Run tests
dart test

# Analyze code
dart analyze

# Run Dart-only examples
dart run example-dartonly/scrcpy_server.dart
dart run example-dartonly/scrcpy_server_parsing.dart
dart run example-dartonly/device_info_example.dart
```

### Flutter Example Application
```bash
# Navigate to example directory
cd example

# Get Flutter dependencies
flutter pub get

# Run the Flutter app
flutter run

# Build for release
flutter build apk --release
flutter build ios --release

# Analyze Flutter code
flutter analyze
```

### Single Test Commands
```bash
# Run specific test file
dart test test/specific_test_file.dart

# Run tests with coverage
dart test --coverage
```

## Architecture

### Core Components

**Dart Implementation (`lib/`)**
- `AdbConnection` - Main connection management (lib/kadb_dart.dart:45)
- `TransportChannel` - Abstraction for different transport mechanisms (lib/transport/)
- `AdbMessageQueue` - Message queuing and handling (lib/queue/)
- `PairingConnectionCtx` - Wireless pairing implementation (lib/pair/)
- `TcpForwarder` - Port forwarding functionality (lib/forwarding/tcp_forwarder.dart)
- `AdbShellStream` - Shell command execution (lib/shell/shell_stream.dart)
- `AdbSyncStream` - File transfer operations (lib/stream/sync_stream.dart)
- Core implementation in `lib/kadb_dart.dart` and supporting modules in subdirectories

### Architecture Modules (Dart Implementation)

**Dart Implementation (`lib/`)**
- `auth/` - Authentication implementations (RSA certificate-based auth)
- `cert/` - Certificate and key management for ADB authentication
- `core/` - Core connection management and protocol constants
- `debug/` - Debugging utilities and logging
- `exception/` - Custom exception classes for ADB protocol errors
- `forwarding/` - Port forwarding functionality (TCP/UDP forwarding)
- `pair/` - Device pairing mechanisms (wireless ADB pairing)
- `queue/` - Message queue management for protocol command handling
- `shell/` - Shell command execution and stream management
- `stream/` - Data stream handling (sync, file, video streams)
- `tls/` - TLS/SSL implementations for secure connections
- `transport/` - Transport channel implementations (USB, network, socket)

### Key Implementation Details

**Authentication Flow:**
- RSA key generation and certificate management (lib/cert/)
- Certificate-based authentication with Android devices
- Support for both paired and unpaired connection modes

**Connection Management:**
- Automatic device discovery and connection establishment
- Robust error handling and reconnection logic
- Support for multiple simultaneous connections

**Protocol Implementation:**
- Complete ADB protocol implementation in pure Dart
- Binary message encoding/decoding (lib/kadb_dart.dart:892)
- Command and response handling through message queue

## Development Workflow

1. **Dart Development**: Use `dart pub get` to install dependencies, `dart analyze` for code quality
2. **Testing**: Run `dart test` for unit tests, `flutter test` for Flutter example app
3. **Code Quality**: Uses `lints` package for Dart code quality enforcement
4. **Flutter Testing**: Use `flutter test` in `example/` directory for Flutter app tests

## Key Dependencies

**Dart Core Package:**
- `pointycastle: ^4.0.0` - Cryptographic operations (RSA, TLS)
- `crypto: ^3.0.3` - Crypto utilities and hashing
- `asn1lib: ^1.0.0` - ASN.1 parsing for certificates
- `typed_data: ^1.3.2` - Utility for working with typed binary data
- `path: ^1.9.0` - Path manipulation utilities

**Flutter Example App:**
- `fvp: ^0.35.0` - FVP video player for TCP streaming
- `video_player: ^2.10.0` - Standard video player
- `path_provider: ^2.1.1` - File system access
- `provider: ^6.1.1` - State management
- `kadb_dart` (local dependency) - Core ADB functionality

## Testing

- **Dart Tests**: Unit tests in `test/` directory using Dart's test framework
- **Flutter Tests**: Widget and integration tests in `example/test/`
- **Manual Testing**: Use Flutter example app for end-to-end testing with real devices
- **Test Coverage**: Run `dart test --coverage` for coverage reports

## RULES
请始终使用中文进行交流