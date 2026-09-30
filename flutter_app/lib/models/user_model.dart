import 'package:supabase_flutter/supabase_flutter.dart';

class UserModel {
  final String id;
  final String username;
  final String nama;
  final String role;

  UserModel({
    required this.id,
    required this.username,
    required this.nama,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username'] as String? ?? '',
      nama: json['nama'] as String? ?? '',
      role: json['role'] as String? ?? 'operator',
    );
  }

  factory UserModel.fromSupabaseUser(User user, [Map<String, dynamic>? profile]) {
    final metadata = user.userMetadata ?? {};
    
    // Extract username from email (e.g., admin@siagenda.local -> admin)
    String username = metadata['username'] ?? profile?['username'] ?? '';
    if (username.isEmpty && user.email != null) {
      username = user.email!.split('@').first;
    }

    final nama = metadata['nama'] ?? profile?['nama'] ?? username;
    final role = metadata['role'] ?? profile?['role'] ?? 'operator';

    return UserModel(
      id: user.id,
      username: username,
      nama: nama,
      role: role,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nama': nama,
      'role': role,
    };
  }

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isOperator => role.toLowerCase() == 'operator';

  String get roleDisplay => isAdmin ? 'Admin' : 'Operator';

  /// Singkatan / short name for outside beranda (header badge) & login subtitle
  /// Examples: "Aptika", "Sandi Kami", "Komunikasi", "Statistik", "Sekretariat", "Admin"
  String get singkatanDisplay {
    final u = username.trim().toLowerCase();
    switch (u) {
      case 'aptika':
        return 'Aptika';
      case 'sandikami':
      case 'sandi kami':
        return 'Sandi Kami';
      case 'komunikasi':
        return 'Komunikasi';
      case 'statistik':
        return 'Statistik';
      case 'sekretariat':
        return 'Sekretariat';
      case 'admin':
        return 'Admin';
      default:
        if (isAdmin) return 'Admin';
        return username.isNotEmpty
            ? '${username[0].toUpperCase()}${username.substring(1)}'
            : 'Operator';
    }
  }

  /// Nama lengkap bidang for inside drawer (e.g. "Aplikasi Informatika")
  String get namaLengkapDisplay {
    final u = username.trim().toLowerCase();
    switch (u) {
      case 'aptika':
        return 'Aplikasi Informatika';
      case 'sandikami':
      case 'sandi kami':
        return 'Persandian dan Keamanan Informasi';
      case 'komunikasi':
        return 'Komunikasi dan Informasi';
      case 'statistik':
        return 'Data dan Statistik';
      case 'sekretariat':
        return 'Sekretariat';
      case 'admin':
        return 'Administrator';
      default:
        if (nama.isNotEmpty && nama.toLowerCase() != 'operator' && nama.toLowerCase() != username.toLowerCase()) {
          return nama;
        }
        return username.isNotEmpty ? username : 'Operator';
    }
  }
}
