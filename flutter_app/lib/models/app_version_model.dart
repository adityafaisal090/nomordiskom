class AppVersionModel {
  final int id;
  final String versionName;
  final int versionCode;
  final String minVersionName;
  final int minVersionCode;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;
  final bool isActive;

  AppVersionModel({
    required this.id,
    required this.versionName,
    required this.versionCode,
    required this.minVersionName,
    required this.minVersionCode,
    required this.downloadUrl,
    required this.changelog,
    required this.forceUpdate,
    required this.isActive,
  });

  factory AppVersionModel.fromJson(Map<String, dynamic> json) {
    return AppVersionModel(
      id: json['id'] as int? ?? 0,
      versionName: json['version_name'] as String? ?? '1.0.0',
      versionCode: json['version_code'] as int? ?? 1,
      minVersionName: json['min_version_name'] as String? ?? '1.0.0',
      minVersionCode: json['min_version_code'] as int? ?? 1,
      downloadUrl: json['download_url'] as String? ?? '',
      changelog: json['changelog'] as String? ?? '',
      forceUpdate: json['force_update'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Check if the server version is newer than current app build
  bool hasUpdate(int currentVersionCode) {
    return versionCode > currentVersionCode;
  }

  /// Check if update is strictly mandatory (cannot be dismissed)
  bool isMandatory(int currentVersionCode) {
    return forceUpdate || currentVersionCode < minVersionCode;
  }
}
