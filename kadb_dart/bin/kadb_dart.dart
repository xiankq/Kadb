
void main(List<String> arguments) {
  print('=== Kadb Dart 命令行工具 ===');
  print('这是一个纯Dart实现的ADB客户端库');
  print('');
  print('使用方法:');
  print('  dart run kadb_dart --help');
  print('');
  print('示例:');
  print('  dart run kadb_dart connect');
  print('  dart run kadb_dart shell "ls -la"');
  print('');
  
  if (arguments.isEmpty) {
    print('使用 --help 查看完整帮助信息');
  }
}
