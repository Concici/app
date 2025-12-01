import 'dart:io';
import 'dart:math';
import 'dart:ui'; // 用于 ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'models/file_item.dart';

// --- 全局日志管理器 (单例) ---
class LogManager extends ChangeNotifier {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final List<String> logs = [];
  final ScrollController scrollController = ScrollController();

  void add(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    logs.add("[$timestamp] $message");
    // 限制日志条数，防止内存溢出
    if (logs.length > 500) logs.removeAt(0);
    notifyListeners();

    // 自动滚动到底部
    if (scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void clear() {
    logs.clear();
    notifyListeners();
  }
}

// 全局便捷日志函数
void appLog(String msg) {
  debugPrint(msg); // 依然输出到 IDE 控制台
  LogManager().add(msg); // 输出到 APP 悬浮窗
}

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );
  runApp(const MyApp());
}

// --- 核心配色与主题 ---
class AppTheme {
  // 核心色：科技蓝 & 紫罗兰
  static const primaryBlue = Color(0xFF2563EB);
  static const accentPurple = Color(0xFF7C3AED);
  static const bgWhite = Color(0xFFF8FAFC);
  static const textDark = Color(0xFF1E293B);
  static const textGrey = Color(0xFF64748B);

  static const double borderRadius = 20.0;

  static BoxShadow softShadow = BoxShadow(
    color: const Color(0xFF64748B).withValues(alpha: 0.08),
    blurRadius: 20,
    offset: const Offset(0, 8),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ether Cloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppTheme.bgWhite,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primaryBlue,
          primary: AppTheme.primaryBlue,
          surface: Colors.white,
        ),
        fontFamily: Platform.isIOS ? ".SF Pro Text" : "Roboto", // 优化字体
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppTheme.primaryBlue,
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
      // 使用 builder 混入全局悬浮控制台
      builder: (context, child) {
        return Stack(children: [child!, const ConsoleOverlay()]);
      },
      home: const HomePage(),
    );
  }
}

// --- 悬浮控制台组件 ---
class ConsoleOverlay extends StatefulWidget {
  const ConsoleOverlay({super.key});

  @override
  State<ConsoleOverlay> createState() => _ConsoleOverlayState();
}

class _ConsoleOverlayState extends State<ConsoleOverlay> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 日志面板 (带动画)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              width: _isOpen ? MediaQuery.of(context).size.width - 40 : 0,
              height: _isOpen ? 300 : 0,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _isOpen ? _buildConsoleContent() : null,
            ),

            // 悬浮按钮 (Floating Toggle)
            GestureDetector(
              onTap: () => setState(() => _isOpen = !_isOpen),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isOpen
                        ? [Colors.redAccent, Colors.deepOrange]
                        : [AppTheme.primaryBlue, AppTheme.accentPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isOpen ? Icons.close : Icons.bug_report_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsoleContent() {
    return Column(
      children: [
        // Console Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "DEV CONSOLE",
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              InkWell(
                onTap: () => LogManager().clear(),
                child: const Icon(
                  Icons.delete_sweep,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        // Console Body
        Expanded(
          child: ListenableBuilder(
            listenable: LogManager(),
            builder: (context, _) {
              final logs = LogManager().logs;
              return ListView.builder(
                controller: LogManager().scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      logs[index],
                      style: const TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontFamily: 'Courier', // 等宽字体模拟终端
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
  List<FileItem> _files = [];
  bool _isListLoading = false;
  final int _maxFilesToShow = 50;
  bool _showAllFiles = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
    appLog("应用启动完成");
  }

  // ... [保留原有的逻辑代码，但替换 print 为 appLog] ...
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
        appLog("自动填充凭证: $username");
      }
    } catch (e) {
      appLog('读取凭证失败: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      _showSnack('请输入账号密码', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    appLog("开始登录: ${_userController.text}");

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
      appLog("登录成功");
      _refreshFiles();
    } catch (e) {
      appLog("登录错误: $e");
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpload(ImageSource source) async {
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
      appLog("选图失败: $e");
      _showSnack('无法打开相册/相机', isError: true);
      return;
    }

    if (files.isEmpty) return;
    appLog("选中 ${files.length} 张图片，准备上传");

    setState(() => _statusText = "正在上传...");
    int success = 0;
    int fail = 0;

    for (int i = 0; i < files.length; i++) {
      setState(() {
        _progress = (i + 1) / files.length;
        _statusText = "正在上传 ${i + 1}/${files.length}";
      });
      try {
        appLog("正在上传: ${files[i].path}");
        await _api.uploadImage(File(files[i].path));
        success++;
      } catch (e) {
        fail++;
        appLog("上传失败: $e");
        if (e.toString().contains('AUTH_EXPIRED')) {
          _logout();
          return;
        }
      }
    }
    _showSnack("任务完成: 成功 $success 张", isError: fail > 0);
    setState(() {
      _statusText = "上传完成";
      _progress = 0.0;
    });
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    setState(() => _isListLoading = true);
    appLog("刷新文件列表...");
    try {
      final list = await _api.fetchFileList();
      setState(() {
        _files = list;
        _showAllFiles = false;
      });
      appLog("获取到 ${list.length} 个文件");
    } catch (e) {
      appLog("刷新失败: $e");
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
      _files = [];
    });
    appLog("用户登出");
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 动态背景：如果已登录显示纯净背景，未登录显示绚丽背景
    return Scaffold(
      extendBodyBehindAppBar: !_isLoggedIn,
      body: Stack(
        children: [
          // 1. 极光背景 (只在登录页显示)
          if (!_isLoggedIn) _buildAmbientBackground(),

          // 2. 内容区
          SafeArea(
            top: false, // 沉浸式
            child: _isLoggedIn ? _buildDashboard() : _buildLoginForm(),
          ),
        ],
      ),
    );
  }

  // --- 高级背景 ---
  Widget _buildAmbientBackground() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white),
      child: Stack(
        children: [
          // 蓝色光斑
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryBlue.withValues(alpha: 0.2),
              ),
            ),
          ),
          // 紫色光斑
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentPurple.withValues(alpha: 0.2),
              ),
            ),
          ),
          // 全局磨砂
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ],
      ),
    );
  }

  // --- 登录界面 (玻璃拟态) ---
  Widget _buildLoginForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          children: [
            const SizedBox(height: 80),
            // Logo 区域
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_queue_rounded,
                size: 50,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '云快拍·用户服务中心',
              style: TextStyle(
                color: AppTheme.textDark,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '瞬间拍照，自动入云',
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: 14,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 60),

            // 玻璃卡片
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _userController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: 'Email / Username',
                          prefixIcon: Icon(
                            Icons.person_outline_rounded,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _passController,
                        obscureText: true,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: 'Password',
                          prefixIcon: Icon(
                            Icons.lock_outline_rounded,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          // 使用 Transform.scale 缩小开关
                          Transform.scale(
                            scale: 0.7, // 【在这里调整大小】0.6-0.8 比较合适
                            child: Switch(
                              value: _rememberMe,
                              activeColor: AppTheme.primaryBlue, // 激活时的颜色
                              activeTrackColor: AppTheme.primaryBlue.withValues(
                                alpha: 0.3,
                              ), // 激活时的轨道颜色
                              inactiveThumbColor: Colors.white, // 关闭时的圆球颜色
                              inactiveTrackColor: Colors.grey[300], // 关闭时的轨道颜色
                              materialTapTargetSize: MaterialTapTargetSize
                                  .shrinkWrap, // 去除多余点击区域边距
                              onChanged: (v) => setState(() => _rememberMe = v),
                            ),
                          ),
                          const SizedBox(width: 4), // 开关和文字之间的间距
                          Text(
                            '记住密码',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          shadowColor: AppTheme.primaryBlue.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- 主控台 (Modern Dashboard) ---
  Widget _buildDashboard() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 120.0,
          floating: true,
          pinned: true,
          elevation: 0,
          backgroundColor: AppTheme.bgWhite,
          surfaceTintColor: Colors.transparent, // 去除滚动时的颜色覆盖
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
            // 核心部分：使用 ShaderMask 给文字“镀”上一层渐变色
            title: ShaderMask(
              blendMode: BlendMode.srcIn, // 关键：将渐变色填充到文字形状里
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  // 【高级渐变色配方】
                  // 这里的配色模拟了"晨曦"到"极光"的过渡：深蓝 -> 艳紫 -> 暖橙
                  colors: [
                    Color(0xFF4361EE), // 电光蓝
                    Color(0xFFD6336C), // 暗紫粉（比F72585柔和）
                    Color(0xFF4CC9F0), // 绿松石
                  ],

                  // 建议把 begin/end 稍微改一点角度，效果更流光
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds);
              },
              child: const Text(
                '我的工作云',
                style: TextStyle(
                  // 注意：这里必须是白色或其他颜色，ShaderMask 会覆盖它，但不能是透明
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900, // 必须用特粗字体，渐变才看得清
                  letterSpacing: -0.5, // 稍微缩紧字间距，显得更精致
                  shadows: [
                    // 加一点点极淡的投影，增加立体感，不至于太飘
                    Shadow(
                      offset: Offset(0, 2),
                      blurRadius: 4,
                      color: Color.fromRGBO(0, 0, 0, 0.05),
                    ),
                  ],
                ),
              ),
            ),

            // 背景保持极简纯白，衬托文字
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: IconButton(
                icon: const Icon(
                  Icons.exit_to_app_rounded,
                  color: AppTheme.textDark,
                ),
                onPressed: _logout,
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [_buildActionArea(), const SizedBox(height: 30)],
            ),
          ),
        ),

        // 文件列表
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: _buildFileListSliver(),
        ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 100)), // 底部留白给控制台
      ],
    );
  }

  Widget _buildActionArea() {
    return Column(
      children: [
        if (_progress > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [AppTheme.softShadow],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      "${(_progress * 100).toInt()}%",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: AppTheme.bgWhite,
                    valueColor: const AlwaysStoppedAnimation(
                      AppTheme.primaryBlue,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

        Row(
          children: [
            Expanded(
              child: _ModernActionButton(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                color: AppTheme.primaryBlue,
                onTap: _isLoading
                    ? null
                    : () => _handleUpload(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ModernActionButton(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                color: AppTheme.accentPurple,
                onTap: _isLoading
                    ? null
                    : () => _handleUpload(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileListSliver() {
    if (_files.isEmpty && !_isListLoading) {
      return SliverToBoxAdapter(
        child: Container(
          height: 200,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 60,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 10),
              Text('No files yet', style: TextStyle(color: Colors.grey[400])),
            ],
          ),
        ),
      );
    }

    if (_isListLoading && _files.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final int displayCount = _showAllFiles
        ? _files.length
        : min(_files.length, _maxFilesToShow);
    final int totalCount = _files.length > _maxFilesToShow && !_showAllFiles
        ? displayCount + 1
        : displayCount;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == displayCount &&
            _files.length > _maxFilesToShow &&
            !_showAllFiles) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _showAllFiles = true),
              child: Text(
                "View remaining ${_files.length - _maxFilesToShow} files",
                style: const TextStyle(color: AppTheme.primaryBlue),
              ),
            ),
          );
        }
        final file = _files[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppTheme.bgWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  file.imgUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Icon(
                    Icons.insert_photo_outlined,
                    color: Colors.grey[400],
                  ),
                ),
              ),
            ),
            title: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              '${file.date} · ${file.size}',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
            trailing: Icon(
              Icons.more_vert_rounded,
              color: Colors.grey[400],
              size: 20,
            ),
          ),
        );
      }, childCount: totalCount),
    );
  }
}

class _ModernActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ModernActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 100,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
