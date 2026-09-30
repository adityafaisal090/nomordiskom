import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda_number_model.dart';

/// Service for agenda number operations — calls Supabase RPC functions.
///
/// All numbering logic (transactions, locking) lives in PostgreSQL functions.
/// This service is a thin wrapper that calls them via `supabase.rpc()`.
///
/// Note: User identity (dibuat_oleh) is determined inside the Postgres
/// function via `auth.uid()` — we do NOT send user_id from the client.
class AgendaService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Issue a number for today (mode: hari_ini)
  /// Calls RPC `issue_today_number` — transaction + FOR UPDATE locking
  /// auth.uid() is used inside the function for dibuat_oleh
  Future<AgendaNumberModel> issueTodayNumber({
    required String kategori,
    required String kodeKlasifikasi,
    required String tujuanSurat,
    required String perihal,
    required String pemohon,
  }) async {
    try {
      final response = await _supabase.rpc('issue_today_number', params: {
        'p_kategori': kategori,
        'p_kode_klasifikasi': kodeKlasifikasi,
        'p_tujuan_surat': tujuanSurat,
        'p_perihal': perihal,
        'p_pemohon': pemohon,
      });

      // RPC RETURNS agenda_numbers → PostgREST serializes composite type as JSON
      final data = response as Map<String, dynamic>;
      return AgendaNumberModel.fromJson(data);
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Issue a backdate number (mode: backdate)
  /// Calls RPC `issue_backdate_number` — takes 1 buffer for the given date
  /// auth.uid() is used inside the function for dibuat_oleh
  Future<AgendaNumberModel> issueBackdateNumber({
    required DateTime tanggal,
    required String kategori,
    required String kodeKlasifikasi,
    required String tujuanSurat,
    required String perihal,
    required String pemohon,
  }) async {
    try {
      final dateStr =
          '${tanggal.year}-${tanggal.month.toString().padLeft(2, '0')}-${tanggal.day.toString().padLeft(2, '0')}';

      final response = await _supabase.rpc('issue_backdate_number', params: {
        'p_tanggal': dateStr,
        'p_kategori': kategori,
        'p_kode_klasifikasi': kodeKlasifikasi,
        'p_tujuan_surat': tujuanSurat,
        'p_perihal': perihal,
        'p_pemohon': pemohon,
      });

      final data = response as Map<String, dynamic>;
      return AgendaNumberModel.fromJson(data);
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Generate daily buffer for a specific date (dev tool / manual trigger)
  /// Calls RPC `generate_daily_buffer`
  Future<void> generateDailyBuffer(DateTime tanggal) async {
    try {
      final dateStr =
          '${tanggal.year}-${tanggal.month.toString().padLeft(2, '0')}-${tanggal.day.toString().padLeft(2, '0')}';

      await _supabase.rpc('generate_daily_buffer', params: {
        'p_tanggal': dateStr,
      });
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Fetch buffer settings per category
  Future<List<Map<String, dynamic>>> getBufferSettings() async {
    try {
      final response = await _supabase.from('buffer_settings').select().order('kategori');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Update buffer setting for a category (Admin only)
  /// Calls RPC `update_buffer_setting`
  Future<void> updateBufferSetting(String kategori, int jumlahBuffer) async {
    try {
      await _supabase.rpc('update_buffer_setting', params: {
        'p_kategori': kategori,
        'p_jumlah': jumlahBuffer,
      });
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Get buffer status (total, available, used) for a specific date and category
  Future<Map<String, int>> getBufferStatusForPeriod(String kategori, DateTime date) async {
    try {
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      var query = _supabase
          .from('agenda_buffers')
          .select('status, nomor, periode')
          .eq('kategori', kategori);

      if (kategori == 'surat_keluar') {
        query = query.eq('periode', dateStr);
      } else {
        // Bulanan: match same year and month
        final startOfMonth = '${date.year}-${date.month.toString().padLeft(2, '0')}-01';
        final nextMonth = date.month == 12 ? DateTime(date.year + 1, 1, 1) : DateTime(date.year, date.month + 1, 1);
        final endOfMonth = '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}-01';
        query = query.gte('periode', startOfMonth).lt('periode', endOfMonth);
      }

      final response = await query;
      final list = response as List;
      int tersedia = 0;
      int terpakai = 0;
      for (final item in list) {
        if (item['status'] == 'tersedia') tersedia++;
        if (item['status'] == 'terpakai') terpakai++;
      }
      return {
        'tersedia': tersedia,
        'terpakai': terpakai,
        'total': list.length,
      };
    } catch (_) {
      return {'tersedia': 0, 'terpakai': 0, 'total': 0};
    }
  }

  /// Generate buffer space for a specific period
  Future<void> generateBufferForPeriod(String kategori, DateTime date) async {
    try {
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await _supabase.rpc('generate_buffer_for_period', params: {
        'p_kategori': kategori,
        'p_periode': dateStr,
      });
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Approve agenda item (Admin only)
  /// Calls RPC `approve_agenda`
  Future<AgendaNumberModel> approveAgenda(int id) async {
    try {
      final response = await _supabase.rpc('approve_agenda', params: {
        'p_id': id,
      });
      final data = response as Map<String, dynamic>;
      return AgendaNumberModel.fromJson(data);
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Reject agenda item (Admin only)
  /// Calls RPC `reject_agenda`
  Future<AgendaNumberModel> rejectAgenda(int id, {String? catatan}) async {
    try {
      final response = await _supabase.rpc('reject_agenda', params: {
        'p_id': id,
        'p_catatan': catatan,
      });
      final data = response as Map<String, dynamic>;
      return AgendaNumberModel.fromJson(data);
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Update agenda draft details while status is 'menunggu' (Operator/Admin)
  /// Calls RPC `update_agenda_draft`
  Future<AgendaNumberModel> updateAgendaDraft({
    required int id,
    required String kodeKlasifikasi,
    required String tujuanSurat,
    required String perihal,
    required String pemohon,
  }) async {
    try {
      final response = await _supabase.rpc('update_agenda_draft', params: {
        'p_id': id,
        'p_kode_klasifikasi': kodeKlasifikasi,
        'p_tujuan_surat': tujuanSurat,
        'p_perihal': perihal,
        'p_pemohon': pemohon,
      });
      final data = response as Map<String, dynamic>;
      return AgendaNumberModel.fromJson(data);
    } catch (e) {
      final message = _extractErrorMessage(e);
      throw Exception(message);
    }
  }

  /// Extract a user-friendly error message from Supabase exceptions
  String _extractErrorMessage(dynamic error) {
    if (error is PostgrestException) {
      // PostgrestException contains the RAISE EXCEPTION message
      final msg = error.message;
      if (msg.contains('FORBIDDEN')) {
        return 'Akses ditolak: Hanya Admin yang dapat mengonfigurasi buffer settings.';
      }
      if (msg.contains('BUFFER_HABIS') || msg.contains('Sudah Habis')) {
        return 'Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
      }
      if (msg.contains('Template tetap belum dikonfigurasi')) {
        return 'Template tetap belum dikonfigurasi. Hubungi admin.';
      }
      return msg;
    }
    final str = error.toString();
    if (str.contains('FORBIDDEN')) {
      return 'Akses ditolak: Hanya Admin yang dapat mengonfigurasi buffer settings.';
    }
    if (str.contains('BUFFER_HABIS') || str.contains('Sudah Habis')) {
      return 'Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
    }
    return str.replaceAll('Exception: ', '');
  }
}
