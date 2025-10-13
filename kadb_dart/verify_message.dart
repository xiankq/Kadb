void main() {
  // 分析连接消息
  final message = [67, 78, 88, 78, 0, 0, 0, 1, 0, 0, 16, 0, 7, 0, 0, 0, 50, 2, 0, 0, 188, 177, 167, 177, 104, 111, 115, 116, 58, 58, 0];
  
  print('=== 连接消息分析 ===');
  
  // 解析消息头
  final command = _readIntLe(message, 0);
  final arg0 = _readIntLe(message, 4);
  final arg1 = _readIntLe(message, 8);
  final payloadLength = _readIntLe(message, 12);
  final checksum = _readIntLe(message, 16);
  final magic = _readIntLe(message, 20);
  
  print('命令: 0x${command.toRadixString(16)} (${_commandToString(command)})');
  print('参数0: 0x${arg0.toRadixString(16)} ($arg0)');
  print('参数1: 0x${arg1.toRadixString(16)} ($arg1)');
  print('负载长度: $payloadLength');
  print('校验和: 0x${checksum.toRadixString(16)} ($checksum)');
  print('魔数: 0x${magic.toRadixString(16)} ($magic)');
  
  // 验证魔数
  final expectedMagic = command ^ 0xFFFFFFFF;
  print('期望魔数: 0x${expectedMagic.toRadixString(16)}');
  print('魔数验证: ${magic == expectedMagic ? '✅ 正确' : '❌ 错误'}');
  
  // 验证校验和
  final payload = message.sublist(24, 24 + payloadLength);
  final calculatedChecksum = _calculateChecksum(payload);
  print('负载: ${String.fromCharCodes(payload)}');
  print('计算校验和: 0x${calculatedChecksum.toRadixString(16)} ($calculatedChecksum)');
  print('校验和验证: ${checksum == calculatedChecksum ? '✅ 正确' : '❌ 错误'}');
  
  // 检查小端序编码
  print('\n=== 小端序验证 ===');
  print('命令字节: ${message.sublist(0, 4)}');
  print('参数0字节: ${message.sublist(4, 8)}');
  print('参数1字节: ${message.sublist(8, 12)}');
  print('负载长度字节: ${message.sublist(12, 16)}');
  print('校验和字节: ${message.sublist(16, 20)}');
  print('魔数字节: ${message.sublist(20, 24)}');
  
  // 重新生成消息进行对比
  print('\n=== 重新生成消息 ===');
  final regenerated = _generateMessage(command, arg0, arg1, payload);
  print('原始消息: $message');
  print('重新生成: $regenerated');
  print('消息匹配: ${_compareMessages(message, regenerated) ? '✅ 匹配' : '❌ 不匹配'}');
}

int _readIntLe(List<int> data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

int _calculateChecksum(List<int> payload) {
  int checksum = 0;
  for (final byte in payload) {
    checksum += byte & 0xFF;
  }
  return checksum;
}

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

List<int> _generateMessage(int command, int arg0, int arg1, List<int> payload) {
  final message = <int>[];
  
  // 写入命令和参数（小端序）
  _writeIntLe(message, command);
  _writeIntLe(message, arg0);
  _writeIntLe(message, arg1);
  
  // 写入负载信息
  _writeIntLe(message, payload.length);
  _writeIntLe(message, _calculateChecksum(payload));
  
  // 写入魔数
  _writeIntLe(message, command ^ 0xFFFFFFFF);
  
  // 写入负载
  message.addAll(payload);
  
  return message;
}

void _writeIntLe(List<int> buffer, int value) {
  buffer.add(value & 0xFF);
  buffer.add((value >> 8) & 0xFF);
  buffer.add((value >> 16) & 0xFF);
  buffer.add((value >> 24) & 0xFF);
}

bool _compareMessages(List<int> msg1, List<int> msg2) {
  if (msg1.length != msg2.length) return false;
  for (int i = 0; i < msg1.length; i++) {
    if (msg1[i] != msg2[i]) return false;
  }
  return true;
}