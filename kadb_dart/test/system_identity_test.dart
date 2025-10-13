import 'package:kadb_dart/kadb_dart.dart';

void main() {
  print('=== 测试系统身份标识生成 ===\n');

  // 测试1: 默认参数
  print('1. 测试默认参数:');
  final defaultIdentity = CertUtils.generateSystemIdentity();
  print('   默认身份: $defaultIdentity\n');

  // 测试2: 自定义用户名和主机名
  print('2. 测试自定义参数:');
  final customIdentity = CertUtils.generateSystemIdentity(
    userName: 'customuser',
    hostName: 'customhost'
  );
  print('   自定义身份: $customIdentity\n');

  // 测试3: 只提供用户名
  print('3. 测试只提供用户名:');
  final userOnlyIdentity = CertUtils.generateSystemIdentity(
    userName: 'testuser',
    hostName: null
  );
  print('   仅用户名: $userOnlyIdentity\n');

  // 测试4: 只提供主机名
  print('4. 测试只提供主机名:');
  final hostOnlyIdentity = CertUtils.generateSystemIdentity(
    userName: null,
    hostName: 'testhost'
  );
  print('   仅主机名: $hostOnlyIdentity\n');

  // 测试5: 验证格式
  print('5. 验证格式:');
  print('   默认格式正确: ${defaultIdentity.contains('@')}');
  print('   自定义格式正确: ${customIdentity.contains('@')}');
  print('   预期值匹配: ${customIdentity == 'customuser@customhost'}\n');

  print('✅ 系统身份标识生成测试完成');
}