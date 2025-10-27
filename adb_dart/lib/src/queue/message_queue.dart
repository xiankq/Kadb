/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';

/// 消息队列接口，定义消息队列的基本操作
abstract class MessageQueue<T> {
  /// 读取下一条消息
  Future<T> readMessage();

  /// 获取本地ID
  int getLocalId(T message);

  /// 获取命令类型
  int getCommand(T message);

  /// 关闭队列
  void close();

  /// 是否是关闭命令
  bool isCloseCommand(T message);

  /// 开始监听消息
  void startListening();

  /// 停止监听消息
  void stopListening();
}
