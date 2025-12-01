// lib/models/file_item.dart

class FileItem {
  final String rid; // 文件唯一ID
  final String name; // 文件名
  final String imgUrl; // 图标或缩略图
  final String size; // 文件大小 (例如 "768 KB")
  final String date; // 上传时间
  final String type; // 类型 (image, attach 等)

  FileItem({
    required this.rid,
    required this.name,
    required this.imgUrl,
    required this.size,
    required this.date,
    required this.type,
  });

  // 工厂方法：负责把服务器的 JSON 转换成 Dart 对象
  factory FileItem.fromJson(Map<String, dynamic> json, String baseUrl) {
    String rawImg = json['img'] ?? '';
    // 处理图片链接：如果是相对路径，就拼上域名
    String fullImgUrl = rawImg.startsWith('http') ? rawImg : '$baseUrl/$rawImg';

    return FileItem(
      rid: json['rid'] ?? '',
      name: json['name'] ?? '未知文件',
      imgUrl: fullImgUrl,
      size: json['fsize'] ?? '',
      date: json['fdateline'] ?? '',
      type: json['type'] ?? 'attach',
    );
  }
}
