import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_version_model.dart';

class UpdateService {
  final _supabase = Supabase.instance.client;
  final _dio = Dio();
  CancelToken? _cancelToken;

  Future<PackageInfo> getCurrentPackageInfo() async {
    return await PackageInfo.fromPlatform();
  }

  Future<AppVersionModel?> checkLatestVersion() async {
    try {
      final response = await _supabase
          .from('app_version')
          .select()
          .eq('is_active', true)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return AppVersionModel.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress, String statusText) onProgress,
  }) async {
    _cancelToken = CancelToken();

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/MONA_latest_update.apk';

      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      onProgress(0.0, 'Memulai unduhan...');

      await _dio.download(
        downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            final percentage = (progress * 100).toInt();
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
            onProgress(
              progress,
              'Mengunduh $receivedMb MB / $totalMb MB ($percentage%)',
            );
          } else {
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            onProgress(0.5, 'Mengunduh $receivedMb MB...');
          }
        },
      );

      onProgress(1.0, 'Membuka instalasi...');

      final result = await OpenFilex.open(
        savePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        throw Exception('Unduhan dibatalkan');
      }
      throw Exception('Gagal mengunduh pembaruan: $e');
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('Cancelled by user');
  }
}
