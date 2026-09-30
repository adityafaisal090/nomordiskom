import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationModel {
  final int id;
  final String userId;
  final String tipe;
  final String judul;
  final String isi;
  final int? agendaId;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.tipe,
    required this.judul,
    required this.isi,
    this.agendaId,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      tipe: json['tipe'] as String,
      judul: json['judul'] as String,
      isi: json['isi'] as String,
      agendaId: json['agenda_id'] as int?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class NotificationService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Fetch notifications for current user
  Future<List<NotificationModel>> fetchNotifications() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    final response = await _supabase
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    return (response as List).map((json) => NotificationModel.fromJson(json)).toList();
  }

  /// Realtime stream for unread notifications count or live notification list
  Stream<List<NotificationModel>> streamNotifications() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return const Stream.empty();

    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((list) => list.map((json) => NotificationModel.fromJson(json)).toList());
  }

  /// Mark notification as read
  Future<void> markAsRead(int notificationId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId)
        .eq('user_id', uid);
  }

  /// Mark all notifications as read for current user
  Future<void> markAllAsRead() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }
}
