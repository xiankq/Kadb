import 'package:adb_dart/adb_dart.dart';
import 'package:test/test.dart';

void main() {
  test('ADB客户端创建测试', () {
    final client = AdbClient.create(host: 'localhost');
    expect(client.host, 'localhost');
    expect(client.port, 5037);
  });
}
