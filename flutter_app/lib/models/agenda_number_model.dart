/// Model class for agenda number records returned from Supabase RPC.
class AgendaNumberModel {
  final int id;
  final int tahun;
  final int nomorAgenda;
  final String nomorLengkap;
  final String kategori;
  final String kodeKlasifikasi;
  final String tujuanSurat;
  final String perihal;
  final String pemohon;
  final String tanggalAgenda;
  final bool isBackdate;
  final String dibuatOleh;
  final String statusAcc;
  final String? catatanAdmin;
  final String createdAt;

  AgendaNumberModel({
    required this.id,
    required this.tahun,
    required this.nomorAgenda,
    required this.nomorLengkap,
    required this.kategori,
    required this.kodeKlasifikasi,
    required this.tujuanSurat,
    required this.perihal,
    required this.pemohon,
    required this.tanggalAgenda,
    required this.isBackdate,
    required this.dibuatOleh,
    required this.statusAcc,
    this.catatanAdmin,
    required this.createdAt,
  });

  factory AgendaNumberModel.fromJson(Map<String, dynamic> json) {
    return AgendaNumberModel(
      id: json['id'] as int? ?? 0,
      tahun: json['tahun'] as int? ?? 0,
      nomorAgenda: json['nomor_agenda'] as int? ?? 0,
      nomorLengkap: json['nomor_lengkap'] as String? ?? '',
      kategori: json['kategori'] as String? ?? '',
      kodeKlasifikasi: json['kode_klasifikasi'] as String? ?? '',
      tujuanSurat: (json['tujuan_surat'] ?? json['kepada']) as String? ?? '',
      perihal: json['perihal'] as String? ?? '',
      pemohon: json['pemohon'] as String? ?? '',
      tanggalAgenda: json['tanggal_agenda']?.toString() ?? '',
      isBackdate: json['is_backdate'] as bool? ?? false,
      dibuatOleh: json['dibuat_oleh']?.toString() ?? '',
      statusAcc: json['status_acc'] as String? ?? 'menunggu',
      catatanAdmin: json['catatan_admin'] as String?,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tahun': tahun,
      'nomor_agenda': nomorAgenda,
      'nomor_lengkap': nomorLengkap,
      'kategori': kategori,
      'kode_klasifikasi': kodeKlasifikasi,
      'tujuan_surat': tujuanSurat,
      'perihal': perihal,
      'pemohon': pemohon,
      'tanggal_agenda': tanggalAgenda,
      'is_backdate': isBackdate,
      'dibuat_oleh': dibuatOleh,
      'status_acc': statusAcc,
      'catatan_admin': catatanAdmin,
      'created_at': createdAt,
    };
  }

  /// Display-friendly category name
  String get kategoriDisplay {
    switch (kategori) {
      case 'surat_keputusan':
        return 'Surat Keputusan';
      case 'nota_dinas':
        return 'Nota Dinas';
      case 'surat_keluar':
        return 'Surat Keluar';
      default:
        return kategori;
    }
  }

  /// Display-friendly status
  String get statusDisplay {
    switch (statusAcc) {
      case 'menunggu':
        return 'Menunggu';
      case 'disetujui':
        return 'Disetujui';
      case 'ditolak':
        return 'Ditolak';
      default:
        return statusAcc;
    }
  }

  /// Formatted creation date (YYYY-MM-DD)
  String get tanggalDibuatDisplay {
    if (createdAt.isEmpty) return '-';
    final dt = DateTime.tryParse(createdAt);
    if (dt != null) {
      final local = dt.toLocal();
      final yyyy = local.year.toString().padLeft(4, '0');
      final mm = local.month.toString().padLeft(2, '0');
      final dd = local.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    }
    if (createdAt.contains('T')) {
      return createdAt.split('T').first;
    }
    return createdAt.split(' ').first;
  }
}

