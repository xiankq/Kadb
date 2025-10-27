import 'dart:typed_data';
import 'dart:async';
import 'package:adb_dart/adb_dart.dart';

/// 完整功能测试脚本
/// 测试adb_dart的所有核心功能
void main() async {
  print('=== adb_dart 完整功能测试 ===');
  print('测试日期: ${DateTime.now()}');
  print('');

  await testRsaFunctionality();
  await testBase64Encoding();
  await testCertificateManagement();
  await testProtocolImplementation();
  await testExceptionHandling();
  await testPairingFunctionality();

  print('');
  print('=== 测试完成 ===');
}

/// 测试RSA加密和认证功能
Future<void> testRsaFunctionality() async {
  print('1. 测试RSA加密和认证功能...');

  try {
    // 生成RSA密钥对
    print('  生成RSA密钥对...');
    final keyPair = await RsaUtils.generateKeyPair();
    print('  ✅ RSA密钥对生成成功');

    // 测试Android公钥格式转换
    print('  测试Android公钥格式转换...');
    final androidFormat = RsaUtils.convertToAndroidFormat(keyPair.publicKey);
    print('  ✅ Android格式转换成功，长度: ${androidFormat.length}');

    // 测试从Android格式解析
    print('  测试从Android格式解析...');
    final parsedPublicKey = RsaUtils.parseFromAndroidFormat(androidFormat);
    print('  ✅ Android格式解析成功');

    // 测试RSA签名和验证
    print('  测试RSA签名和验证...');
    final testData = Uint8List.fromList('Hello ADB!'.codeUnits);
    final signature = await RsaUtils.sign(testData, keyPair.privateKey);
    final isValid = await RsaUtils.verify(
      testData,
      signature,
      keyPair.publicKey,
    );

    if (isValid) {
      print('  ✅ RSA签名和验证成功');
    } else {
      print('  ❌ RSA签名验证失败');
    }
  } catch (e) {
    print('  ❌ RSA功能测试失败: $e');
  }

  print('');
}

/// 测试Base64编码功能
Future<void> testBase64Encoding() async {
  print('2. 测试Base64编码功能...');

  try {
    // 测试标准Base64编码
    print('  测试标准Base64编码...');
    final testData = Uint8List.fromList('Hello World!'.codeUnits);
    final encoded = Base64Utils.encode(testData);
    final decoded = Base64Utils.decode(encoded);

    if (decoded.length == testData.length &&
        decoded.every((i) => testData.contains(i))) {
      print('  ✅ 标准Base64编码测试成功');
    } else {
      print('  ❌ 标准Base64编码测试失败');
    }

    // 测试URL安全Base64编码
    print('  测试URL安全Base64编码...');
    final urlEncoded = Base64Utils.encodeUrl(testData);
    final urlDecoded = Base64Utils.decodeUrl(urlEncoded);

    if (urlDecoded.length == testData.length) {
      print('  ✅ URL安全Base64编码测试成功');
    } else {
      print('  ❌ URL安全Base64编码测试失败');
    }

    // 测试Base64验证
    print('  测试Base64验证...');
    final isValid = Base64Utils.isValidBase64(encoded);
    if (isValid) {
      print('  ✅ Base64验证测试成功');
    } else {
      print('  ❌ Base64验证测试失败');
    }
  } catch (e) {
    print('  ❌ Base64编码测试失败: $e');
  }

  print('');
}

/// 测试证书管理功能
Future<void> testCertificateManagement() async {
  print('3. 测试证书管理功能...');

  try {
    // 测试加载密钥对
    print('  测试加载密钥对...');
    final keyPair = await CertUtils.loadKeyPair();
    print('  ✅ 密钥对加载成功');

    // 测试公钥格式
    print('  测试公钥格式...');
    final adbFormat = await keyPair.toAdbFormat();
    print('  ✅ ADB格式公钥生成成功，长度: ${adbFormat.length}');

    // 测试签名功能
    print('  测试签名功能...');
    final testPayload = Uint8List.fromList('device::test'.codeUnits);
    final testMessage = AdbMessage(
      command: 0x434e584e, // CNXN
      arg0: 0x01000000,    // version
      arg1: 0x00100000,    // max payload
      payloadLength: testPayload.length,
      checksum: AdbProtocol.getPayloadChecksum(testPayload, 0, testPayload.length),
      magic: 0x434e584e ^ 0xffffffff,
      payload: testPayload,
    );
    
    final signature = await keyPair.signPayload(testMessage);
    print('  ✅ 消息签名成功，签名长度: ${signature.length}');
  } catch (e) {
    print('  ❌ 证书管理测试失败: $e');
  }

  print('');
}

/// 测试协议实现
Future<void> testProtocolImplementation() async {
  print('4. 测试协议实现...');

  try {
    // 测试协议常量
    print('  测试协议常量...');
    print('  ✅ ADB协议版本: ${AdbProtocol.connectVersion}');
    print('  ✅ 最大载荷大小: ${AdbProtocol.connectMaxData}');

    // 测试消息创建
    print('  测试消息创建...');
    final payload = Uint8List.fromList('host::test'.codeUnits);
    final message = AdbMessage(
      command: AdbProtocol.cmdCnxc,
      arg0: AdbProtocol.connectVersion,
      arg1: AdbProtocol.connectMaxData,
      payloadLength: payload.length,
      checksum: AdbProtocol.getPayloadChecksum(payload, 0, payload.length),
      magic: AdbProtocol.cmdCnxc ^ 0xffffffff,
      payload: payload,
    );

    print('  ✅ 消息创建成功，命令: 0x${message.command.toRadixString(16)}');

    // 测试校验和
    print('  测试校验和...');
    final checksum = AdbProtocol.getPayloadChecksum(
      message.payload,
      0,
      message.payload.length,
    );
    print('  ✅ 校验和计算成功: 0x${checksum.toRadixString(16)}');
  } catch (e) {
    print('  ❌ 协议实现测试失败: $e');
  }

  print('');
}

/// 测试异常处理
Future<void> testExceptionHandling() async {
  print('5. 测试异常处理...');

  try {
    // 测试各种异常类型
    print('  测试连接异常...');
    final connException = AdbConnectionException(
      '连接失败',
      null,
      'localhost',
      5037,
    );
    print('  ✅ 连接异常创建成功: $connException');

    print('  测试流异常...');
    final streamException = AdbStreamException('流错误', null, 123);
    print('  ✅ 流异常创建成功: $streamException');

    print('  测试协议异常...');
    final protocolException = AdbProtocolException(
      '协议错误',
      null,
      0x12345678,
      1,
      2,
    );
    print('  ✅ 协议异常创建成功: $protocolException');

    print('  测试超时异常...');
    final timeoutException = AdbTimeoutException(
      '操作超时',
      const Duration(seconds: 30),
    );
    print('  ✅ 超时异常创建成功: $timeoutException');

    // 测试异常包装
    print('  测试异常包装...');
    final wrappedException = ExceptionUtils.wrapException(
      StateError('测试错误'),
      '包装测试',
    );
    print('  ✅ 异常包装成功: $wrappedException');
  } catch (e) {
    print('  ❌ 异常处理测试失败: $e');
  }

  print('');
}

/// 测试配对功能
Future<void> testPairingFunctionality() async {
  print('6. 测试配对功能...');

  try {
    // 测试配对认证上下文
    print('  测试配对认证上下文...');
    final rsaKeyPair = await RsaUtils.generateKeyPair();

    // 创建AdbKeyPair
    final keyPair = AdbKeyPair(
      privateKey: Uint8List.fromList(
        rsaKeyPair.privateKey.modulus + rsaKeyPair.privateKey.privateExponent,
      ),
      publicKey: Uint8List.fromList(
        rsaKeyPair.publicKey.modulus + rsaKeyPair.publicKey.exponent,
      ),
    );

    final pairingCode = Uint8List.fromList('123456'.codeUnits);
    const deviceName = 'TestDevice';

    final authCtx = PairingAuthCtx(
      keyPair: keyPair,
      pairingCode: pairingCode,
      deviceName: deviceName,
    );

    // 测试配对码验证
    final isValid = authCtx.verifyPairingCode(pairingCode);
    if (isValid) {
      print('  ✅ 配对码验证成功');
    } else {
      print('  ❌ 配对码验证失败');
    }

    // 测试配对响应创建
    print('  测试配对响应创建...');
    final response = authCtx.createPairingResponse();
    print('  ✅ 配对响应创建成功，长度: ${response.length}');

    // 测试配对响应验证
    final isResponseValid = authCtx.verifyPairingResponse(response);
    if (isResponseValid) {
      print('  ✅ 配对响应验证成功');
    } else {
      print('  ❌ 配对响应验证失败');
    }
  } catch (e) {
    print('  ❌ 配对功能测试失败: $e');
  }

  print('');
}

/// 测试完整连接流程（模拟）
Future<void> testConnectionFlow() async {
  print('7. 测试完整连接流程（模拟）...');

  try {
    // 创建ADB客户端
    print('  创建ADB客户端...');
    final client = AdbClient(host: 'localhost', port: 5037);

    print('  ✅ ADB客户端创建成功');

    // 测试客户端API
    print('  测试客户端API...');
    print('  ✅ 连接状态检查: ${client.isConnected}');

    // 注意：这里没有实际连接到ADB服务器，只是测试API
    print('  ✅ 客户端API测试完成');
  } catch (e) {
    print('  ❌ 连接流程测试失败: $e');
  }

  print('');
}
