import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:permission_handler/permission_handler.dart'; // 如果不需要手动处理权限，可注释
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // 1. 引入安全存储库
import 'api_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CloudSync',
      debugShowCheckedModeBanner: false, // 去掉右上角 Debug 标签
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  // 2. 创建安全存储实例
  final _storage = const FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool _isLoading = false;
  // 3. 新增状态：记住密码开关 (默认开启)
  bool _rememberMe = true;

  String _statusText = "";
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    // 4. App 启动时读取历史账号
    _loadCredentials();
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  // 读取逻辑
  Future<void> _loadCredentials() async {
    try {
      final username = await _storage.read(key: 'username');
      final password = await _storage.read(key: 'password');

      if (username != null && password != null) {
        setState(() {
          _userController.text = username;
          _passController.text = password;
          _rememberMe = true; // 如果读到了，默认勾选
        });
      }
    } catch (e) {
      debugPrint('读取凭证失败: $e');
    }
  }

  // 登录动作
  Future<void> _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      _showSnack('请输入账号密码');
      return;
    }

    setState(() => _isLoading = true);
    // 收起键盘
    FocusScope.of(context).unfocus();

    try {
      await _api.login(_userController.text, _passController.text);

      // 5. 登录成功后：处理密码保存逻辑
      if (_rememberMe) {
        await _storage.write(key: 'username', value: _userController.text);
        await _storage.write(key: 'password', value: _passController.text);
      } else {
        // 如果用户没勾选，就清除旧数据
        await _storage.delete(key: 'username');
        await _storage.delete(key: 'password');
      }

      setState(() {
        _isLoggedIn = true;
        _statusText = "准备就绪";
      });
    } catch (e) {
      _showSnack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 上传动作
  Future<void> _handleUpload(ImageSource source) async {
    // 权限检查逻辑 (Android 自动处理)

    // 选图
    final ImagePicker picker = ImagePicker();
    List<XFile> files = [];

    try {
      if (source == ImageSource.camera) {
        final XFile? photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
        );
        if (photo != null) files.add(photo);
      } else {
        files = await picker.pickMultiImage(imageQuality: 80);
      }
    } catch (e) {
      _showSnack('无法打开相册/相机: $e');
      return;
    }

    if (files.isEmpty) return;

    // 开始队列上传
    setState(() => _statusText = "正在上传...");
    int success = 0;
    int fail = 0;

    for (int i = 0; i < files.length; i++) {
      setState(() {
        _progress = (i + 1) / files.length;
        _statusText = "正在上传 ${i + 1}/${files.length}";
      });

      try {
        await _api.uploadImage(File(files[i].path));
        success++;
      } catch (e) {
        fail++;
        if (e.toString().contains('AUTH_EXPIRED')) {
          _showSnack('登录已失效，请重新登录');
          _logout();
          return;
        }
      }
    }

    _showSnack("任务结束: 成功 $success, 失败 $fail");
    setState(() {
      _statusText = "上传完成";
      _progress = 0.0;
    });
  }

  void _logout() {
    _api.logout();
    setState(() {
      _isLoggedIn = false;
      // 注销时不清空输入框，方便下次登录
      // _userController.clear();
      // _passController.clear();
      _statusText = "";
      _progress = 0.0;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 80,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 20),
              Text(
                'CloudSync',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
              const SizedBox(height: 40),

              if (!_isLoggedIn) ...[
                // --- 登录视图 ---
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _userController,
                        decoration: const InputDecoration(
                          labelText: '账号',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 6. 新增 UI：记住密码勾选框
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            activeColor: Colors.blueAccent,
                            onChanged: (value) {
                              setState(() {
                                _rememberMe = value!;
                              });
                            },
                          ),
                          const Text('记住密码'),
                        ],
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  '安全登录',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // --- 上传视图 ---
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.blueAccent.withOpacity(0.2),
                            child: const Icon(
                              Icons.person,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '欢迎回来',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _userController.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _logout,
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.redAccent,
                            ),
                            tooltip: '退出登录',
                          ),
                        ],
                      ),
                      const Divider(height: 30),

                      if (_statusText.isNotEmpty) ...[
                        Text(
                          _statusText,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (_progress > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: LinearProgressIndicator(
                            value: _progress,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.camera_alt,
                              label: '拍照',
                              color: Colors.blue,
                              onTap: () => _handleUpload(ImageSource.camera),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.photo_library,
                              label: '相册',
                              color: Colors.purple,
                              onTap: () => _handleUpload(ImageSource.gallery),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 小组件：大按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
