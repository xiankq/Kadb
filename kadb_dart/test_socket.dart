import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main() async {
  print('测试Socket连接到ADB服务器...');
  
  try {
    // 直接使用Dart的Socket.connect测试连接
    final socket = await Socket.connect('127.0.0.1', 5037, timeout: Duration(seconds: 5));
    print('✅ Socket连接成功！');
    
    // 创建正确的ADB连接消息
    final connectMessage = _createConnectMessage();
    socket.add(connectMessage);
    await socket.flush();
    print('✅ ADB连接消息发送成功 (${connectMessage.length} 字节)');
    
    // 监听响应
    final completer = Completer<List<int>>();
    final buffer = <int>[];
    late StreamSubscription<List<int>> subscription;
    final timer = Timer(Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(TimeoutException('等待响应超时'));
      }
    });
    
    subscription = socket.listen(
      (data) {
        print('收到数据块: ${data.length} 字节');
        buffer.addAll(data);
        
        // 如果收到完整的消息头（24字节），尝试解析
        if (buffer.length >= 24 && !completer.isCompleted) {
          completer.complete(List<int>.from(buffer));
          timer.cancel();
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
          timer.cancel();
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          if (buffer.isNotEmpty) {
            completer.complete(List<int>.from(buffer));
          } else {
            completer.completeError(Exception('连接已关闭，未收到响应'));
          }
          timer.cancel();
        }
      },
    );
    
    try {
      final response = await completer.future;
      print('✅ 收到响应: ${response.length} 字节');
      
      // 解析响应消息头
      if (response.length >= 24) {
        final command = _readIntLe(response, 0);
        final arg0 = _readIntLe(response, 4);
        final arg1 = _readIntLe(response, 8);
        final payloadLength = _readIntLe(response, 12);
        final checksum = _readIntLe(response, 16);
        final magic = _readIntLe(response, 20);
        
        print('响应消息头:');
        print('  命令: 0x${command.toRadixString(16)}');
        print('  参数0: $arg0');
        print('  参数1: $arg1');
        print('  负载长度: $payloadLength');
        print('  校验和: $checksum');
        print('  魔数: 0x${magic.toRadixString(16)}');
        
        // 验证魔数
        if ((command ^ magic) == 0xFFFFFFFF) {
          print('✅ 魔数验证成功');
        } else {
          print('❌ 魔数验证失败');
        }
        
        // 如果有负载数据，显示前几个字节
        if (response.length > 24) {
          final payload = response.sublist(24, response.length);
          print('负载数据 (前100字节): ${payload.take(100).toList()}');
        }
      }
    } catch (e) {
      print('❌ 等待响应失败: $e');
    } finally {
      subscription.cancel();
    }
    
    // 关闭连接
    await socket.close();
    print('✅ Socket连接已关闭');
    
  } catch (e) {
    print('❌ Socket连接失败: $e');
  }
}

/// 创建ADB连接消息
Uint8List _createConnectMessage() {
  // ADB协议连接消息格式
  final command = 0x4e584e43; // CNXN
  final version = 0x01000000; // 版本1.0.0
  final maxData = 0x00100000; // 1MB最大数据
  final payload = 'host::\u0000'.codeUnits;
  
  final message = Uint8List(24 + payload.length);
  var offset = 0;
  
  // 写入消息头
  _writeIntLe(message, offset, command); offset += 4;
  _writeIntLe(message, offset, version); offset += 4;
  _writeIntLe(message, offset, maxData); offset += 4;
  _writeIntLe(message, offset, payload.length); offset += 4;
  _writeIntLe(message, offset, _payloadChecksum(payload)); offset += 4;
  _writeIntLe(message, offset, command ^ 0xFFFFFFFF); offset += 4;
  
  // 写入负载
  for (var i = 0; i < payload.length; i++) {
    message[offset + i] = payload[i];
  }
  
  return message;
}

/// 计算负载校验和
int _payloadChecksum(List<int> payload) {
  int checksum = 0;
  for (final byte in payload) {
    checksum += byte & 0xFF;
  }
  return checksum;
}

/// 以小端序写入32位整数
void _writeIntLe(Uint8List buffer, int offset, int value) {
  buffer[offset] = value & 0xFF;
  buffer[offset + 1] = (value >> 8) & 0xFF;
  buffer[offset + 2] = (value >> 16) & 0xFF;
  buffer[offset + 3] = (value >> 24) & 0xFF;
}

/// 从小端序字节数组中读取32位整数
int _readIntLe(List<int> data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}