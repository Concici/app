// lib/main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'models/file_item.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CloudSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 调整主题颜色为更现代的蓝色
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue.shade700),
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
  final _storage = const FlutterSecureStorage();

  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _rememberMe = true;

  String _statusText = "";
  double _progress = 0.0;

  // 文件列表状态
  List<FileItem> _files = [];
  bool _isListLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    try {
      final username = await _storage.read(key: 'username');
      final password = await _storage.read(key: 'password');

      if (username != null && password != null) {
        setState(() {
          _userController.text = username;
          _passController.text = password;
          _rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint('读取凭证失败: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      _showSnack('请输入账号密码');
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      await _api.login(_userController.text, _passController.text);

      if (_rememberMe) {
        await _storage.write(key: 'username', value: _userController.text);
        await _storage.write(key: 'password', value: _passController.text);
      } else {
        await _storage.delete(key: 'username');
        await _storage.delete(key: 'password');
      }

      setState(() {
        _isLoggedIn = true;
        _statusText = "准备就绪";
      });

      // 登录成功后立即拉取列表
      _refreshFiles();
    } catch (e) {
      _showSnack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpload(ImageSource source) async {
    // ... (上传选择逻辑不变) ...
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

    // 上传成功后，刷新列表
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    setState(() => _isListLoading = true);
    try {
      final list = await _api.fetchFileList();
      setState(() {
        _files = list;
      });
    } catch (e) {
      // 避免在列表上显示 Toast，只在 debug 打印
      debugPrint('获取文件列表失败: $e');
    } finally {
      setState(() => _isListLoading = false);
    }
  }

  void _logout() {
    _api.logout();
    setState(() {
      _isLoggedIn = false;
      _statusText = "";
      _progress = 0.0;
      _files = []; // 清空文件列表
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ============== UI 拆分与重构 ==============

  @override
  Widget build(BuildContext context) {
    // 核心改动：根据登录状态渲染不同的主视图
    return Scaffold(
      backgroundColor: Colors.grey[50], // 更浅的背景色
      body: SafeArea(
        // 确保内容不被刘海屏遮挡
        // 登录状态下使用 Dashboard (Column + Expanded)
        child: _isLoggedIn ? _buildDashboard() : _buildLoginFormView(),
      ),
    );
  }

  // 登录视图 (需要 SingleChildScrollView 以防键盘弹出时内容溢出)
  Widget _buildLoginFormView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_upload_outlined,
              size: 80,
              color: Color(0xFF1E88E5), // Material Blue 600
            ),
            const SizedBox(height: 20),
            Text(
              'CloudSync Login',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 40),

            // 登录表单卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
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
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        activeColor: Theme.of(context).colorScheme.primary,
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
                          : const Text('安全登录', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 仪表盘视图 (采用 Column + Expanded 结构)
  Widget _buildDashboard() {
    return Column(
      children: [
        // 顶部上传控制区
        _buildUploadControls(),

        // 文件列表头部
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '目录文件列表',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _refreshFiles,
                icon: _isListLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, color: Colors.blue),
              ),
            ],
          ),
        ),

        // 列表主体 (Expanded 确保列表占据剩余空间并可滚动)
        Expanded(child: _buildFileList()),
      ],
    );
  }

  // 上传控制区 (固定高度)
  Widget _buildUploadControls() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
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
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.1),
                radius: 20,
                child: Icon(
                  Icons.person,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '欢迎回来',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                tooltip: '退出登录',
              ),
            ],
          ),
          const Divider(height: 30),

          if (_statusText.isNotEmpty) ...[
            Text(_statusText, style: TextStyle(color: Colors.grey[700])),
            const SizedBox(height: 10),
          ],

          if (_progress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(
                value: _progress,
                borderRadius: BorderRadius.circular(5),
                minHeight: 8,
              ),
            ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.camera_alt,
                  label: '拍照上传',
                  color: Colors.blue.shade600,
                  onTap: _isLoading
                      ? null
                      : () => _handleUpload(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ActionButton(
                  icon: Icons.photo_library,
                  label: '从相册选择',
                  color: Colors.purple.shade600,
                  onTap: _isLoading
                      ? null
                      : () => _handleUpload(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 文件列表组件
  Widget _buildFileList() {
    if (_files.isEmpty && !_isListLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 8),
            const Text('目录为空，请上传文件', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Card(
            elevation: 1, // 稍微有点阴影
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  file.imgUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) {
                    // 如果图片加载失败，显示默认文件图标
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.insert_drive_file,
                        color: Colors.blueGrey[400],
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
              title: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${file.date}  ·  ${file.size}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              // trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () {
                _showSnack('点击了文件: ${file.name}');
                // TODO: 这里可以实现文件下载或预览功能
              },
            ),
          ),
        );
      },
    );
  }
}

// 小组件：大按钮 (保持不变)
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap; // 允许为 null (在加载时禁用)

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
      // 使用 Opacity 来表示禁用状态
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          height: 100, // 略微调小高度
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
