import 'package:kadb_dart/kadb_dart.dart';

/// 系统身份标识生成测试
void main() {
  // 测试默认参数
  final defaultIdentity = CertUtils.generateSystemIdentity();
  assert(defaultIdentity.contains('@'), '默认身份应包含@符号');

  // 测试自定义参数
  final customIdentity = CertUtils.generateSystemIdentity(
    userName: 'customuser',
    hostName: 'customhost'
  );
  assert(customIdentity == 'customuser@customhost', '自定义身份格式应正确');

  // 测试部分参数
  final userOnlyIdentity = CertUtils.generateSystemIdentity(
    userName: 'testuser',
    hostName: null
  );
  assert(userOnlyIdentity.contains('@'), '仅用户名时应生成完整身份');

  final hostOnlyIdentity = CertUtils.generateSystemIdentity(
    userName: null,
    hostName: 'testhost'
  );
  assert(hostOnlyIdentity.contains('@'), '仅主机名时应生成完整身份');

  // 测试通过
  print('系统身份标识生成测试通过');
}