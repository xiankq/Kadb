/// Shell命令响应类
///
/// 封装Shell命令执行的结果，包括标准输出、标准错误和退出码
library;

/// Shell命令执行响应
class AdbShellResponse {
  /// 标准输出内容
  final String output;

  /// 标准错误内容
  final String errorOutput;

  /// 退出码
  final int exitCode;

  /// 构造函数
  const AdbShellResponse({
    required this.output,
    required this.errorOutput,
    required this.exitCode,
  });

  /// 获取合并的输出（stdout + stderr）
  String get allOutput {
    if (output.isEmpty) return errorOutput;
    if (errorOutput.isEmpty) return output;
    return '$output$errorOutput';
  }

  /// 检查命令是否成功执行（退出码为0）
  bool get isSuccess => exitCode == 0;

  /// 检查命令是否失败（退出码非0）
  bool get isFailure => exitCode != 0;

  /// 获取输出的行列表（按行分割）
  List<String> get outputLines {
    if (output.isEmpty) return [];
    return output.split('\n');
  }

  /// 获取错误输出的行列表（按行分割）
  List<String> get errorLines {
    if (errorOutput.isEmpty) return [];
    return errorOutput.split('\n');
  }

  /// 获取所有输出的行列表（按行分割）
  List<String> get allLines {
    if (allOutput.isEmpty) return [];
    return allOutput.split('\n');
  }

  /// 去除输出两端的空白字符
  AdbShellResponse trimmed() {
    return AdbShellResponse(
      output: output.trim(),
      errorOutput: errorOutput.trim(),
      exitCode: exitCode,
    );
  }

  /// 转换为调试字符串
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('Shell响应 (退出码: $exitCode)');

    if (output.isNotEmpty) {
      buffer.write('\n标准输出:\n$output');
    }

    if (errorOutput.isNotEmpty) {
      buffer.write('\n标准错误:\n$errorOutput');
    }

    return buffer.toString();
  }

  /// 转换为简洁的调试字符串
  String toBriefString() {
    if (isSuccess) {
      return '命令执行成功 (退出码: $exitCode)';
    } else {
      return '命令执行失败 (退出码: $exitCode)';
    }
  }

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'output': output,
      'errorOutput': errorOutput,
      'exitCode': exitCode,
      'isSuccess': isSuccess,
    };
  }

  /// 从JSON格式创建响应
  factory AdbShellResponse.fromJson(Map<String, dynamic> json) {
    return AdbShellResponse(
      output: json['output'] ?? '',
      errorOutput: json['errorOutput'] ?? '',
      exitCode: json['exitCode'] ?? -1,
    );
  }

  /// 创建空的失败响应
  factory AdbShellResponse.emptyFailure({int exitCode = 1}) {
    return AdbShellResponse(
      output: '',
      errorOutput: '',
      exitCode: exitCode,
    );
  }

  /// 创建空的成功响应
  factory AdbShellResponse.emptySuccess() {
    return AdbShellResponse(
      output: '',
      errorOutput: '',
      exitCode: 0,
    );
  }

  /// 创建包含输出的成功响应
  factory AdbShellResponse.success(String output) {
    return AdbShellResponse(
      output: output,
      errorOutput: '',
      exitCode: 0,
    );
  }

  /// 创建包含输出的失败响应
  factory AdbShellResponse.failure(String errorOutput, {int exitCode = 1}) {
    return AdbShellResponse(
      output: '',
      errorOutput: errorOutput,
      exitCode: exitCode,
    );
  }

  /// 创建包含输出和错误的失败响应
  factory AdbShellResponse.failureWithOutput(
    String output,
    String errorOutput, {
    int exitCode = 1,
  }) {
    return AdbShellResponse(
      output: output,
      errorOutput: errorOutput,
      exitCode: exitCode,
    );
  }

  /// 合并多个响应
  static AdbShellResponse merge(List<AdbShellResponse> responses) {
    if (responses.isEmpty) {
      return AdbShellResponse.emptySuccess();
    }

    final output = StringBuffer();
    final errorOutput = StringBuffer();
    int finalExitCode = 0;

    for (final response in responses) {
      if (response.output.isNotEmpty) {
        output.write(response.output);
        if (!response.output.endsWith('\n')) {
          output.write('\n');
        }
      }

      if (response.errorOutput.isNotEmpty) {
        errorOutput.write(response.errorOutput);
        if (!response.errorOutput.endsWith('\n')) {
          errorOutput.write('\n');
        }
      }

      if (response.isFailure) {
        finalExitCode = response.exitCode;
      }
    }

    return AdbShellResponse(
      output: output.toString(),
      errorOutput: errorOutput.toString(),
      exitCode: finalExitCode,
    );
  }
}
