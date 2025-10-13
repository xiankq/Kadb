import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/core/adb_message.dart';
import 'package:kadb_dart/core/adb_protocol.dart';
import 'package:kadb_dart/core/adb_reader.dart';
import 'package:kadb_dart/core/adb_writer.dart';
import 'package:kadb_dart/queue/adb_message_queue.dart';
import 'package:kadb_dart/stream/adb_stream.dart';
import 'package:kadb_dart/transport/transport_channel.dart' as base;
import 'package:kadb_dart/transport/socket_transport_channel.dart';

/// ADB连接类
/// 管理ADB协议连接、认证和流操作
class AdbConnection {
  static const int _maxId = 0x7FFFFFFF;

  final AdbKeyPair _keyPair;
  final Duration ioTimeout;
  final bool _debug;

  late AdbMessageQueue _messageQueue;
  late AdbWriter _writer;
  late base.TransportChannel _currentChannel;
  int _nextLocalId = 1;
  final Map<int, AdbStream> _streams = {};
  bool _closed = false;

  /// 创建ADB连接
  /// [keyPair] ADB密钥对
  /// [ioTimeout] IO操作超时时间
  /// [debug] 是否启用调试模式
  AdbConnection({
    required AdbKeyPair keyPair,
    this.ioTimeout = const Duration(seconds: 30),
    bool debug = false,
  }) : _keyPair = keyPair,
       _debug = debug;

  /// 连接到ADB服务器
  /// [host] 主机地址
  /// [port] 端口号
  /// [useTls] 是否使用TLS加密
  Future<void> connect(String host, int port, {bool useTls = false}) async {
    if (_closed) {
      throw StateError('连接已关闭');
    }

    // 创建Socket传输通道
    final socketChannel = SocketTransportChannel();
    await socketChannel.connect(host, port, timeout: ioTimeout);
    _currentChannel = socketChannel;

    // 创建读写器
    final reader = AdbReader((int length) async {
      final buffer = Uint8List(length);
      await _currentChannel.readExactly(buffer, ioTimeout);
      return buffer.toList();
    });

    _writer = AdbWriter((List<int> data) async {
      await _currentChannel.write(Uint8List.fromList(data), ioTimeout);
    });

    // 创建消息队列
    _messageQueue = AdbMessageQueue(reader);

    // 发送初始连接请求
    await _writer.writeConnect(
      version: AdbProtocol.version,
      maxData: AdbProtocol.maxPayload,
      systemIdentityString: 'host::${_generateSystemIdentity()}',
    );

    // 处理连接和认证流程
    AdbMessage message;
    while (true) {
      message = await _messageQueue.next();

      switch (message.command) {
        case AdbProtocol.cmdStls:
          // 处理TLS升级
          await _writer.writeStls(message.arg0);

          // 暂时不支持TLS升级，直接抛出异常
          throw UnsupportedError('TLS升级功能暂未实现');
          break;

        case AdbProtocol.CMD_AUTH:
          // 处理认证（简化认证流程，与Kotlin版本一致）
          if (message.arg0 != AdbProtocol.authTypeToken) {
            throw Exception('不支持的认证类型: ${message.arg0}');
          }

          // 关键修复：只对payload进行签名，与Kotlin版本保持一致
          // Kotlin版本: val signature = keyPair.signPayload(message)
          // 重要：使用message.payloadLength来限制payload的实际长度
          final actualPayload = message.payload.sublist(0, message.payloadLength);

          // 调试输出：显示token信息
          if (_debug) {
            print('调试: 收到AUTH token，长度=${message.payloadLength}');
            final tokenHex = actualPayload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
            print('调试: token内容=$tokenHex');
          }

          final signature = _keyPair.signAdbMessagePayload(actualPayload);

          // 调试输出：显示签名信息
          if (_debug) {
            print('调试: 生成签名，长度=${signature.length}');
            final sigHex = signature.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
            print('调试: 签名前8字节=$sigHex');
          }

          // 发送签名响应
          await _writer.writeAuth(AdbProtocol.authTypeSignature, signature);

          // 等待设备响应签名验证结果
          message = await _messageQueue.next();

          // 如果设备接受签名，应该返回CNXN消息
          if (message.command == AdbProtocol.CMD_CNXN) {
            // 认证成功，继续连接流程
            break;
          }

          // 如果设备拒绝签名，会返回AUTH消息要求公钥认证
          if (message.command == AdbProtocol.CMD_AUTH) {
            // 发送公钥进行认证
            final publicKey = _generateAdbPublicKey(_keyPair);
            await _writer.writeAuth(
              AdbProtocol.authTypeRsapublickey,
              publicKey,
            );

            // 等待最终认证结果
            message = await _messageQueue.next();

            // 检查认证结果
            if (message.command != AdbProtocol.CMD_CNXN) {
              throw Exception('公钥认证失败: 期望CNXN消息，收到${message.command}');
            }
            break;
          }

          // 其他情况都是认证失败
          throw Exception('认证失败: 期望CNXN或AUTH消息，收到${message.command}');

        case AdbProtocol.CMD_CNXN:
          // 连接成功，跳出整个循环
          break;

        default:
          throw Exception('未知的连接消息: ${message.command}');
      }

      // 如果收到CNXN消息，跳出整个循环
      if (message.command == AdbProtocol.CMD_CNXN) {
        break;
      }
    }

    if (_debug) {
      print('ADB连接成功建立');
    }
  }

  /// 生成ADB格式的公钥（修复格式问题）
  /// [keyPair] ADB密钥对
  List<int> _generateAdbPublicKey(AdbKeyPair keyPair) {
    // 使用Android ADB要求的特定格式：Base64编码的Android RSA公钥 + 空格 + 用户名@主机名@软件名 + 空字符
    final publicKeyBytes = _convertRsaPublicKeyToAdbFormat(keyPair.publicKey);
    final base64Key = base64.encode(publicKeyBytes);
    final deviceName = _generateSystemIdentity();

    // 关键修复：使用与Kotlin版本完全一致的格式，包括多余的大括号
    // Kotlin版本：Base64.encodeToByteArray(bytes) + " ${defaultDeviceName()}}".encodeToByteArray()
    final fullKey = '$base64Key $deviceName}\u0000';

    return utf8.encode(fullKey);
  }

  /// 将RSA公钥转换为ADB格式（与Kotlin版本一致）
  /// [publicKey] RSA公钥
  /// 返回ADB格式的字节数组
  List<int> _convertRsaPublicKeyToAdbFormat(RSAPublicKey publicKey) {
    /*
     * ADB直接将RSAPublicKey结构体保存到文件中。
     *
     * typedef struct RSAPublicKey {
     * int len; // n[]的长度，以uint32_t为单位
     * uint32_t n0inv;  // -1 / n[0] mod 2^32
     * uint32_t n[RSANUMWORDS]; // 模数，小端序数组
     * uint32_t rr[RSANUMWORDS]; // R^2，小端序数组
     * int exponent; // 3或65537
     * } RSAPublicKey;
     */

    const keyLengthBits = 2048;
    const keyLengthBytes = 256; // 2048/8
    const keyLengthWords = 64; // 256/4

    final r32 = BigInt.from(1) << 32;
    final n = publicKey.modulus!;
    final r = BigInt.from(1) << (keyLengthWords * 32);
    var rr = r.modPow(BigInt.from(2), n);
    final rem = n % r32;
    final n0inv = rem.modInverse(r32);

    final myN = List<int>.filled(keyLengthWords, 0);
    final myRr = List<int>.filled(keyLengthWords, 0);

    // 与Kotlin版本完全一致：在一个循环中先处理R^2，再处理模数n
    var tempRr = rr;
    var tempN = n;
    for (int i = 0; i < keyLengthWords; i++) {
      // 先处理R^2
      final rrRes = tempRr ~/ r32;
      final rrRemainder = tempRr % r32;
      tempRr = rrRes;
      myRr[i] = rrRemainder.toInt();

      // 再处理模数n
      final nRes = tempN ~/ r32;
      final nRemainder = tempN % r32;
      tempN = nRes;
      myN[i] = nRemainder.toInt();
    }

    // 构建字节缓冲区（小端序）
    final buffer = BytesBuilder();

    // 写入长度（小端序）
    _writeIntLe(buffer, keyLengthWords);

    // 写入n0inv（小端序）
    _writeIntLe(buffer, (-n0inv).toInt());

    // 写入模数n（小端序）
    for (int i = 0; i < keyLengthWords; i++) {
      _writeIntLe(buffer, myN[i]);
    }

    // 写入R^2（小端序）
    for (int i = 0; i < keyLengthWords; i++) {
      _writeIntLe(buffer, myRr[i]);
    }

    // 写入指数（小端序）
    _writeIntLe(buffer, publicKey.publicExponent!.toInt());

    return buffer.toBytes();
  }

  /// 以小端序写入32位整数到字节缓冲区
  void _writeIntLe(BytesBuilder buffer, int value) {
    buffer.addByte(value & 0xFF);
    buffer.addByte((value >> 8) & 0xFF);
    buffer.addByte((value >> 16) & 0xFF);
    buffer.addByte((value >> 24) & 0xFF);
  }

  /// 将BigInt转换为字节数组
  List<int> _bigIntToBytes(BigInt value) {
    var data = value.toUnsigned(value.bitLength).toRadixString(16);
    if (data.length % 2 != 0) {
      data = '0$data';
    }

    final result = <int>[];
    for (int i = 0; i < data.length; i += 2) {
      result.add(int.parse(data.substring(i, i + 2), radix: 16));
    }

    return result;
  }

  /// 编码长度字段
  List<int> _encodeLength(int length) {
    if (length < 128) {
      return [length];
    } else {
      final bytes = <int>[];
      var value = length;
      while (value > 0) {
        bytes.insert(0, value & 0xFF);
        value >>= 8;
      }
      bytes.insert(0, bytes.length | 0x80);
      return bytes;
    }
  }

  /// 生成系统标识字符串（与Kotlin版本完全一致）
  /// 关键修复：确保每次连接使用相同的系统标识，这对重连认证至关重要
  /// Kotlin版本格式：$userName@$hostName@$software
  String _generateSystemIdentity() {
    // 尝试获取一致的用户名和主机名
    final userName = Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        Platform.environment['LOGNAME'] ??
        'user';
    final hostName = Platform.environment['COMPUTERNAME'] ??
        Platform.environment['HOSTNAME'] ??
        Platform.environment['HOST'] ??
        'localhost';

    // 确保使用一致的标识符格式，避免特殊字符
    final sanitizedUserName = userName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final sanitizedHostName = hostName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    // 关键修复：添加软件标识符，与Kotlin版本保持一致
    // Kotlin版本："$userName@$hostName@$software"
    return '$sanitizedUserName@$sanitizedHostName@Kadb';
  }

  /// 打开ADB流
  /// [destination] 目标服务
  Future<AdbStream> open(String destination) async {
    if (_closed) {
      throw StateError('连接已关闭');
    }

    final localId = _newId();
    final stream = AdbStream(
      localId: localId,
      remoteId: 0,
      destination: destination,
      messageQueue: _messageQueue,
      writer: _writer,
      debug: _debug,
    );

    _streams[localId] = stream;

    // 发送打开流请求
    await _writer.writeOpen(localId, destination);

    // 等待远程ID分配
    await stream.waitForRemoteId();

    return stream;
  }

  /// 生成新的本地ID
  int _newId() {
    final id = _nextLocalId;
    _nextLocalId = (_nextLocalId + 1) % _maxId;
    return id;
  }

  /// 关闭连接
  void close() {
    if (!_closed) {
      _closed = true;
      _messageQueue.close();
      _currentChannel.close();

      // 关闭所有打开的流
      for (final stream in _streams.values) {
        stream.close();
      }
      _streams.clear();
    }
  }

  /// 检查连接是否关闭
  bool get isClosed => _closed;

  /// 检查是否支持特定功能（占位实现）
  /// [feature] 功能名称
  /// 返回是否支持该功能
  bool supportsFeature(String feature) {
    // 目前返回false，后续根据实际功能实现
    return false;
  }
}
