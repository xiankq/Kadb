import 'package:pointycastle/export.dart';

void main() {
  print('PointyCastle export import successful');
  
  // 测试RSAEngine和PKCS1Encoding的导入
  try {
    // 尝试创建RSAEngine实例
    final rsaEngine = RSAEngine();
    print('RSAEngine import successful');
  } catch (e) {
    print('RSAEngine import failed: $e');
  }
  
  try {
    // 尝试创建PKCS1Encoding实例
    final pkcs1 = PKCS1Encoding(RSAEngine());
    print('PKCS1Encoding import successful');
  } catch (e) {
    print('PKCS1Encoding import failed: $e');
  }
}