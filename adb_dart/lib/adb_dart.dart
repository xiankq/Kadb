/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

// library adb_dart;

// 核心功能导出
export 'src/adb_client.dart';
export 'src/core/adb_connection.dart';
export 'src/core/adb_message.dart';
export 'src/core/adb_protocol.dart';

// Shell功能导出
export 'src/shell/adb_shell_response.dart';
export 'src/shell/adb_shell_stream.dart';
export 'src/shell/adb_shell_packet.dart';
export 'src/shell/adb_shell_packet_v2.dart';

// 流功能导出
export 'src/stream/adb_stream.dart';

// 证书功能导出
export 'src/cert/adb_key_pair.dart';
export 'src/cert/cert_utils.dart';
export 'src/cert/rsa_utils.dart';
export 'src/cert/base64_utils.dart';
export 'src/cert/android_pubkey.dart';

// Sync功能导出
export 'src/sync/adb_sync_stream.dart';

// 转发功能导出
export 'src/forwarding/tcp_forwarder.dart';

// 队列功能导出
export 'src/queue/adb_message_queue.dart';
export 'src/queue/message_queue.dart';

// 异常处理导出
export 'src/exception/adb_exceptions.dart';

// 传输层功能导出
export 'src/transport/transport_channel.dart';
export 'src/transport/transport_factory.dart';
export 'src/transport/socket_transport_channel.dart';
export 'src/transport/tls_transport_channel.dart';

// 调试功能导出
export 'src/debug/logging.dart';

// 证书平台功能导出
export 'src/cert/platform/default_device_name.dart';

// TLS功能导出
export 'src/tls/tls_error_mapper.dart';

// 配对功能导出
export 'src/pair/pairing_auth_ctx.dart';
export 'src/pair/pairing_connection_ctx.dart';
export 'src/pair/ssl_utils.dart';
