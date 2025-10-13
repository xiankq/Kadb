import 'dart:async';
import 'dart:convert';
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
import 'package:kadb_dart/transport/tls_nio_channel.dart';

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
  }) : _keyPair = keyPair, _debug = debug;
  
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
          // 处理认证
          if (message.arg0 != AdbProtocol.authTypeToken) {
            throw Exception('不支持的认证类型: ${message.arg0}');
          }
          
          // 签名负载
          final signature = _keyPair.signAdbMessage(AdbMessage(
            command: message.command,
            arg0: message.arg0,
            arg1: message.arg1,
            payloadLength: message.payloadLength,
            checksum: 0, // 认证消息不需要校验和
            magic: AdbProtocol.ADB_HEADER_LENGTH,
            payload: Uint8List.fromList(message.payload),
          ));
          await _writer.writeAuth(AdbProtocol.authTypeSignature, signature);
          
          // 读取下一条消息
          message = await _messageQueue.next();
          
          // 如果还是AUTH消息，发送公钥
          if (message.command == AdbProtocol.CMD_AUTH) {
            final publicKey = _generateAdbPublicKey(_keyPair);
            await _writer.writeAuth(AdbProtocol.authTypeRsapublickey, publicKey);
            
            // 读取最终认证结果
            message = await _messageQueue.next();
          }
          
          // 检查是否是CNXN连接确认
          if (message.command != AdbProtocol.CMD_CNXN) {
            throw Exception('认证失败: 期望CNXN消息，收到${message.command}');
          }
          break;
          
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
  
  /// 生成ADB格式的公钥（与Kotlin版本一致）
  /// [keyPair] ADB密钥对
  List<int> _generateAdbPublicKey(AdbKeyPair keyPair) {
    // 使用与Kotlin版本一致的Android RSA公钥格式转换
    final publicKeyBytes = _convertRsaPublicKeyToAdbFormat(keyPair.publicKey);
    
    // 转换为Base64编码，并添加设备名称后缀（与Kotlin版本一致）
    final base64Key = base64.encode(publicKeyBytes);
    final deviceName = 'Dart-ADB-1.0.0';
    final fullKey = '$base64Key $deviceName}';
    
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
    const keyLengthBytes = keyLengthBits ~/ 8;
    const keyLengthWords = keyLengthBytes ~/ 4;
    
    final r32 = BigInt.from(1) << 32;
    final n = publicKey.modulus!;
    final r = BigInt.from(1) << (keyLengthWords * 32);
    var rr = r.modPow(BigInt.from(2), n);
    final rem = n % r32;
    final n0inv = rem.modInverse(r32);
    
    final myN = List<int>.filled(keyLengthWords, 0);
    final myRr = List<int>.filled(keyLengthWords, 0);
    
    // 处理模数n
    var tempN = n;
    for (int i = 0; i < keyLengthWords; i++) {
      final res = tempN ~/ r32;
      final remainder = tempN % r32;
      tempN = res;
      myN[i] = remainder.toInt();
    }
    
    // 处理R^2
    var tempRr = rr;
    for (int i = 0; i < keyLengthWords; i++) {
      final res = tempRr ~/ r32;
      final remainder = tempRr % r32;
      tempRr = res;
      myRr[i] = remainder.toInt();
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
  
  /// 生成系统标识字符串
  String _generateSystemIdentity() {
    return 'Dart-ADB-1.0.0';
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