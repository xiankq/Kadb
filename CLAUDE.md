# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kadb is a Kotlin Multiplatform library that enables connecting to Android devices without requiring the ADB server. It supports wireless debugging, APK installation, file management, port forwarding, and shell command execution. The project also includes a Dart implementation (`kadb_dart`) and a Compose Desktop test application.

## Repository Structure

- `kadb/` - Main Kotlin Multiplatform library
  - `src/commonMain/kotlin/` - Shared Kotlin code
  - `src/androidMain/kotlin/` - Android-specific implementations
  - `src/jvmMain/kotlin/` - JVM-specific implementations
- `kadb-test-app/` - Compose Desktop test application
- `kadb_dart/` - Dart implementation of the ADB protocol
- `adbDocumentation/` - ADB protocol documentation
- `scrcpy/` - Related scrcpy integration code

## Build Commands

### Kotlin Multiplatform Library
```bash
# Build all targets
./gradlew build

# Run tests
./gradlew test

# Publish to Maven Local
./gradlew publishToMavenLocal

# Build specific target
./gradlew :kadb:build
```

### Dart Package
```bash
cd kadb_dart

# Get dependencies
dart pub get

# Run tests
dart test

# Analyze code
dart analyze
```

### Test Application
```bash
# Run the Compose Desktop test app
./gradlew :kadb-test-app:run

# Build native distributions
./gradlew :kadb-test-app:createDistributable
```

## Architecture

### Core Components

**Kotlin Multiplatform Library (`kadb/`)**
- `AdbConnection` - Main connection management
- `AdbProtocol` - ADB protocol implementation
- `TransportChannel` - Abstraction for different transport mechanisms
- `AdbMessageQueue` - Message queuing and handling
- `PairingConnectionCtx` - Wireless pairing implementation
- `TcpForwarder` - Port forwarding functionality
- `AdbShellStream` - Shell command execution
- `AdbSyncStream` - File transfer operations

**Dart Implementation (`kadb_dart/`)**
- Similar architecture to Kotlin version
- `AdbConnection` - Connection management
- `TransportChannel` - Transport layer abstraction
- `AdbMessageQueue` - Message handling
- `PairingConnectionCtx` - Device pairing
- `TcpForwarder` - Port forwarding
- `AdbShellStream` - Shell operations

### Platform-Specific Implementations

**Android Target:**
- Uses `DocumentFile` for file operations
- Includes `HiddenApiBypass` for Android Q compatibility
- Platform-specific device name detection

**JVM Target:**
- Uses jmDNS for device discovery
- Conscrypt for SSL/TLS support
- NIO-based transport channels

## Development Workflow

1. **Kotlin Development**: Use `./gradlew build` to compile all targets
2. **Testing**: Run `./gradlew test` for Kotlin, `dart test` for Dart
3. **Code Quality**: Both projects use linting (`kotlin.code.style=official` for Kotlin, `lints` package for Dart)
4. **Pairing Implementation**: Note that device pairing currently has limitations on JVM target

## Key Dependencies

**Kotlin:**
- `kotlinx.coroutines.core` - Coroutines support
- `okio` - I/O operations
- `bcprov`/`bcpkix` - Cryptographic operations
- `spake2` - Authentication protocol

**Dart:**
- `pointycastle` - Cryptographic operations
- `crypto` - Crypto utilities
- `asn1lib` - ASN.1 parsing

## Testing

- Kotlin: JUnit tests in `src/commonTest/kotlin/` and `src/jvmTest/kotlin/`
- Dart: Tests in `test/` directory using Dart's test framework
- Test application in `kadb-test-app/` provides GUI testing capabilities