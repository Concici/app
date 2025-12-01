import 'dart:io';
import 'package:flutter/foundation.dart'; // 用于 debugPrint
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import 'models/file_item.dart'; // 👈 记得引入刚才建的模型
import 'dart:convert';

class ApiService {
  // 单例模式：确保全局只使用一个网络实例和 Cookie 管理器
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;
  late PersistCookieJar _cookieJar; // Cookie 持久化存储

  // 基础配置
  final String baseUrl = 'http://cloud.xuny-sat.com:8881';
  final String containerId = '947'; // 默认上传目录ID947

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        // 关键：响应类型设为纯文本，方便我们自己解析 HTML/JSON
        responseType: ResponseType.plain,
        headers: {
          // 伪装成 PC 浏览器，防止服务器返回精简版手机页面
          "User-Agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Referer": baseUrl,
        },
      ),
    );
    _initCookieManager();
  }

  // 初始化 Cookie 管理器 (存放在手机应用文档目录)
  void _initCookieManager() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String appDocPath = appDocDir.path;
    _cookieJar = PersistCookieJar(
      storage: FileStorage("$appDocPath/.cookies/"),
    );
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  // ==========================================
  //               核心业务方法
  // ==========================================

  /// 登录逻辑 (Clean Slate 模式)
  /// 每次登录前强制清空旧会话，确保获取全新的 formhash
  Future<bool> login(String username, String password) async {
    try {
      debugPrint('--- 开始全新的登录流程 (Clean Slate) ---');

      // 1. 【关键】强制清空本地 Cookie
      // 这一步是为了防止“会话固定”问题，确保服务器把我们当做新用户处理
      await _cookieJar.deleteAll();

      // 2. 访问登录页，获取表单信息
      final pageResponse = await _dio.get('/user.php?mod=login');
      String html = pageResponse.data.toString();

      // 3. 正则提取 FormHash
      // 注意：\s+ 兼容了 name 和 value 之间的空格
      final hashMatch = RegExp(
        r'name="formhash"\s+value="([^"]+)"',
      ).firstMatch(html);

      if (hashMatch == null) {
        // 打印部分 HTML 以便调试
        debugPrint(
          '❌ 异常 HTML: ${html.substring(0, html.length > 500 ? 500 : html.length)}',
        );
        throw Exception('环境异常：无法获取登录表单(formhash)');
      }

      String formHash = hashMatch.group(1)!;
      debugPrint('🔑 获取新 formhash: $formHash');

      // 4. 提交账号密码
      final loginResponse = await _dio.post(
        '/user.php?mod=login&op=logging&action=login&loginsubmit=yes',
        data: {
          'email': username, // DzzOffice 要求的字段名是 email
          'password': password,
          'loginsubmit': 'true',
          'formhash': formHash,
          'referer': '$baseUrl/./',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      String resHtml = loginResponse.data.toString();
      debugPrint(
        '📩 服务器返回片段: ${resHtml.substring(0, resHtml.length > 200 ? 200 : resHtml.length)}...',
      );

      // 5. 结果校验 (超级白名单)

      // A. 优先检查 JSON 成功标志 (你抓包发现的格式)
      if (resHtml.contains('"success":')) {
        debugPrint('✅ 登录成功 (JSON模式)');
        return true;
      }

      // B. 检查 HTML 成功标志 (兼容旧版或跳转页)
      bool isHtmlSuccess =
          resHtml.contains('action=logout') ||
          resHtml.contains('user_login') ||
          resHtml.contains('退出') ||
          resHtml.contains('欢迎您回来') ||
          resHtml.contains('现在将转入');

      if (isHtmlSuccess) {
        debugPrint('✅ 登录成功 (HTML模式)');
        return true;
      }

      // 6. 失败判定
      if (resHtml.contains('密码错误') || resHtml.contains('name="password"')) {
        throw Exception('账号或密码错误');
      }

      debugPrint('❌ 未知响应，判定为失败');
      throw Exception('登录验证未通过');
    } catch (e) {
      debugPrint('❌ 认证流程异常: $e');
      rethrow; // 把错误抛给 UI 层显示
    }
  }

  /// 上传图片
  Future<void> uploadImage(File file) async {
    try {
      String fileName = file.path.split('/').last;

      // 构建 Multipart 表单
      FormData formData = FormData.fromMap({
        'files[]': await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _dio.post(
        '/index.php?mod=explorer&op=ajax&operation=uploads&container=$containerId',
        data: formData,
      );

      if (response.statusCode == 200) {
        String body = response.data.toString();

        // 检查：如果上传时服务器返回了 HTML 登录框，说明 Cookie 失效了
        if (body.trim().startsWith('<') && body.contains('name="password"')) {
          throw Exception('AUTH_EXPIRED');
        }

        debugPrint('✅ 上传成功: $fileName');
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ 上传失败: $e');
      rethrow;
    }
  }

  // --- 新增：获取文件列表 ---
  // 👇👇👇 新增的方法 👇👇👇
  Future<List<FileItem>> fetchFileList() async {
    try {
      debugPrint('📥 正在获取文件列表...');

      final response = await _dio.get(
        '/index.php?mod=explorer&op=explorerfile&do=filelist&sid=f-$containerId',
      );

      // 解析 JSON
      Map<String, dynamic> jsonResponse;
      if (response.data is String) {
        jsonResponse = jsonDecode(response.data);
      } else {
        jsonResponse = response.data;
      }

      // 提取 data 字段
      // 注意：API 返回的 data 是一个 Map，key 是 id，value 是文件信息
      var dataObj = jsonResponse['data'];

      if (dataObj == null || dataObj is! Map) {
        return []; // 没有文件
      }

      List<FileItem> fileList = [];
      // 遍历 Map 的 values
      for (var item in dataObj.values) {
        fileList.add(FileItem.fromJson(item, baseUrl));
      }
      fileList.sort((a, b) => b.date.compareTo(a.date));
      debugPrint('✅ 获取到 ${fileList.length} 个文件');
      return fileList;
    } catch (e) {
      debugPrint('❌ 获取文件列表失败: $e');
      rethrow;
    }
  }

  /// 注销
  Future<void> logout() async {
    try {
      // 1. 告诉服务器注销 Session
      await _dio.get('/user.php?mod=login&op=logging&action=logout');
      // 2. 清除本地保存的 Cookie
      await _cookieJar.deleteAll();
      debugPrint('Session 已安全清除');
    } catch (e) {
      debugPrint('注销异常: $e');
    }
  }
}
