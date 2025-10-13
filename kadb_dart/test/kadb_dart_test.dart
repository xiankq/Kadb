import 'package:kadb_dart/kadb_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Kadb Dart 测试', () {
    test('ADB协议常量测试', () {
      expect(AdbProtocol.ADB_HEADER_LENGTH, equals(24));
      expect(AdbProtocol.CMD_CNXN, equals(0x4e584e43));
      expect(AdbProtocol.CMD_AUTH, equals(0x48545541));
    });

    test('ADB消息创建测试', () {
      final message = AdbMessage(
        command: AdbProtocol.CMD_AUTH,
        arg0: 1,
        arg1: 0,
        payloadLength: 10,
        checksum: 123,
        magic: 0,
        payload: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
      
      expect(message.command, equals(AdbProtocol.CMD_AUTH));
      expect(message.arg0, equals(1));
      expect(message.payload.length, equals(10));
    });

    test('ADB密钥对生成测试', () async {
      final keyPair = await AdbKeyPair.generate();
      expect(keyPair, isNotNull);
      expect(keyPair.publicKey, isNotNull);
      expect(keyPair.privateKey, isNotNull);
      expect(keyPair.publicKey.modulus, isNotNull);
      expect(keyPair.privateKey.modulus, isNotNull);
    });
  });
}
