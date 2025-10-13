import 'dart:async';
import 'dart:io';

import 'package:kadb_dart/core/adb_protocol.dart';

void main() async {
  print('=== ADB连接调试程序 ===');
  
  try {
    // 1. 测试Socket连接
    print('1. 测试Socket连接...');
    final socket = await Socket.connect('127.0.0.1', 5037, timeout: Duration(seconds: 5));
    print('✅ Socket连接成功');
    
    // 2. 生成连接消息
    print('2. 生成ADB连接消息...');
    final connectMessage = AdbProtocol.generateMessageWithOffset(
      AdbProtocol.CMD_CNXN,
      AdbProtocol.connectVersion,
      AdbProtocol.connectMaxdata,
      AdbProtocol.connectPayload,
      0,
      AdbProtocol.connectPayload.length,
    );
    
    print('连接消息长度: ${connectMessage.length} 字节');
    print('连接消息内容: $connectMessage');
    
    // 3. 发送连接消息
    print('3. 发送连接消息...');
    socket.add(connectMessage);
    await socket.flush();
    print('✅ 连接消息发送成功');
    
    // 4. 监听响应
    print('4. 等待响应...');
    final completer = Completer<List<int>>();
    final buffer = <int>[];
    late StreamSubscription<List<int>> subscription;
    final timer = Timer(Duration(seconds: 5), () {
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
        print('  命令: 0x${command.toRadixString(16)} (${_commandToString(command)})');
        print('  参数0: $arg0 (0x${arg0.toRadixString(16)})');
        print('  参数1: $arg1 (0x${arg1.toRadixString(16)})');
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
          print('负载数据 (字符串): ${String.fromCharCodes(payload)}');
        }
      }
    } catch (e) {
      print('❌ 等待响应失败: $e');
    } finally {
      subscription.cancel();
    }
    
    // 5. 关闭连接
    await socket.close();
    print('✅ Socket连接已关闭');
    
  } catch (e) {
    print('❌ 调试失败: $e');
  }
}

/// 从小端序字节数组中读取32位整数
int _readIntLe(List<int> data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

/// 将命令代码转换为字符串
String _commandToString(int command) {
  switch (command) {
    case 0x48545541: return 'AUTH';
    case 0x4e584e43: return 'CNXN';
    case 0x4e45504f: return 'OPEN';
    case 0x59414b4f: return 'OKAY';
    case 0x45534c43: return 'CLSE';
    case 0x45545257: return 'WRTE';
    case 0x534c5453: return 'STLS';
    default: return 'UNKNOWN';
  }
}