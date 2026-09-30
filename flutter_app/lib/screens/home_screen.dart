import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../models/agenda_number_model.dart';
import '../services/agenda_service.dart';
import '../services/notification_service.dart';
import '../services/fcm_service.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import '../theme/app_theme.dart';

/// Home screen matching wireframe 02-home-operator.png:
/// - Dark top section: Header branding + Big floating + button
/// - Content area below:
///   - 3 date selector pills (Year / Month / Date) — tappable to change
///   - Search bar + Sort by button (filterable by category)
///   - List of agenda numbers fetched from Supabase with status color badges:
///     - Orange: Menunggu (Pending)
///     - Green: Disetujui
///     - Red: Ditolak
///   - Hamburger menu contains user info & logout
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _selectedYear;
  late int _selectedMonthIndex; // 1-based
  int? _selectedDay;
  bool _showSuggestions = false;

  // Sort / filter by category
  String _sortCategory = 'Semua'; // 'Semua', 'Surat Keluar', 'Nota Dinas', 'Surat Keputusan'

  int _adminTabIndex = 0; // 0 = Belum ACC, 1 = Sudah ACC

  // Real agenda data from Supabase
  List<AgendaNumberModel> _realAgendaList = [];
  bool _isLoadingRealData = false;

  // Realtime subscription & Deep-linking
  RealtimeChannel? _agendaRealtimeChannel;
  int? _highlightedAgendaId;

  /// Fetch real agenda numbers from Supabase table
  Future<void> _fetchRealAgendaNumbers({bool isBackgroundSync = false}) async {
    if (!mounted) return;
    if (!isBackgroundSync) {
      setState(() {
        _isLoadingRealData = true;
      });
    }

    try {
      final response = await Supabase.instance.client
          .from('agenda_numbers')
          .select()
          .order('created_at', ascending: false);

      final list = (response as List)
          .map((json) => AgendaNumberModel.fromJson(json as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _realAgendaList = list;
          _isLoadingRealData = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRealData = false);
      }
    }
  }

  /// Setup Supabase Realtime channel to automatically sync agenda changes across devices
  void _setupRealtimeAgendaSubscription() {
    _agendaRealtimeChannel = Supabase.instance.client
        .channel('public:agenda_numbers')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'agenda_numbers',
          callback: (payload) {
            _fetchRealAgendaNumbers(isBackgroundSync: true);
          },
        )
        .subscribe();
  }

  /// Handle deep-linking when user taps a push or in-app notification with agenda_id
  void _handleNotificationTap(String agendaIdStr) {
    final agendaId = int.tryParse(agendaIdStr);
    if (agendaId == null) return;

    final index = _realAgendaList.indexWhere((item) => item.id == agendaId);
    if (index != -1) {
      final item = _realAgendaList[index];
      final itemDate = DateTime.tryParse(item.tanggalAgenda);
      if (itemDate != null && mounted) {
        setState(() {
          _selectedYear = itemDate.year;
          _selectedMonthIndex = itemDate.month;
          _selectedDay = itemDate.day;
          _highlightedAgendaId = agendaId;
          _searchController.clear();
          if (item.statusAcc == 'menunggu') {
            _adminTabIndex = 0;
          } else {
            _adminTabIndex = 1;
          }
        });
      }
    } else {
      _fetchRealAgendaNumbers(isBackgroundSync: true).then((_) {
        final newIndex = _realAgendaList.indexWhere((item) => item.id == agendaId);
        if (newIndex != -1 && mounted) {
          final item = _realAgendaList[newIndex];
          final itemDate = DateTime.tryParse(item.tanggalAgenda);
          if (itemDate != null) {
            setState(() {
              _selectedYear = itemDate.year;
              _selectedMonthIndex = itemDate.month;
              _selectedDay = itemDate.day;
              _highlightedAgendaId = agendaId;
              _searchController.clear();
              if (item.statusAcc == 'menunggu') {
                _adminTabIndex = 0;
              } else {
                _adminTabIndex = 1;
              }
            });
          }
        }
      });
    }
  }

  /// Get filtered real agenda data based on search, sort, date, and admin tab
  List<AgendaNumberModel> _getFilteredRealData(String role) {
    final query = _searchController.text.toLowerCase().trim();
    return _realAgendaList.where((item) {
      // Filter by category
      if (_sortCategory != 'Semua' && item.kategoriDisplay != _sortCategory) {
        return false;
      }
      // Filter by admin tab
      if (role == 'Admin') {
        if (_adminTabIndex == 0 && item.statusAcc != 'menunggu') return false;
        if (_adminTabIndex == 1 && item.statusAcc == 'menunggu') return false;
      }
      // Filter by date selector pills (Tahun / Bulan / Tanggal) when NOT searching
      if (query.isEmpty) {
        final itemDate = DateTime.tryParse(item.tanggalAgenda);
        if (itemDate != null) {
          if (itemDate.year != _selectedYear ||
              itemDate.month != _selectedMonthIndex ||
              (_selectedDay != null && itemDate.day != _selectedDay)) {
            return false;
          }
        }
      }
      // Filter by search query when searching (allows search across all dates)
      if (query.isNotEmpty) {
        final searchFields = [
          item.perihal,
          item.nomorLengkap,
          item.kategoriDisplay,
          item.tujuanSurat,
          item.pemohon,
          item.kodeKlasifikasi,
        ].join(' ').toLowerCase();
        if (!searchFields.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  /// Get search suggestions based on current input
  List<String> _getSuggestions() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return [];
    final suggestions = <String>{};
    for (final item in _realAgendaList) {
      for (final field in [item.perihal, item.nomorLengkap, item.tujuanSurat]) {
        if (field.toLowerCase().contains(query)) {
          suggestions.add(field);
        }
      }
    }
    return suggestions.take(5).toList();
  }

  StreamSubscription? _notifSubscription;
  int _lastKnownUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonthIndex = now.month;
    _selectedDay = now.day;

    _fetchRealAgendaNumbers();
    _setupRealtimeAgendaSubscription();
    _listenToLiveNotifications();

    // Hook FCM deep-linking callback
    FcmService().onNotificationTap = _handleNotificationTap;
    FcmService().registerCurrentToken();
  }

  @override
  void dispose() {
    _agendaRealtimeChannel?.unsubscribe();
    _notifSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _listenToLiveNotifications() {
    _notifSubscription = NotificationService().streamNotifications().listen((notifications) {
      final unread = notifications.where((n) => !n.isRead).length;
      if (unread > _lastKnownUnreadCount && notifications.isNotEmpty) {
        final latest = notifications.first;
        if (mounted && !latest.isRead) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
              ),
              elevation: 6,
              duration: const Duration(seconds: 4),
              content: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/app_logo.jpeg',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primary, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(latest.judul, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(latest.isi, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          _fetchRealAgendaNumbers();
        }
      }
      _lastKnownUnreadCount = unread;
    });
  }

  String _getMonthName(int month) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return months[month - 1];
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  // ── Year Picker ──
  void _pickYear() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Pilih Tahun', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 280,
            height: 300,
            child: YearPicker(
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              selectedDate: DateTime(_selectedYear),
              onChanged: (DateTime dateTime) {
                setState(() {
                  _selectedYear = dateTime.year;
                  // Clamp day if set
                  final maxDay = _daysInMonth(_selectedYear, _selectedMonthIndex);
                  if (_selectedDay != null && _selectedDay! > maxDay) {
                    _selectedDay = maxDay;
                  }
                });
                Navigator.pop(ctx);
              },
            ),
          ),
        );
      },
    );
  }

  // ── Month Picker ──
  void _pickMonth() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Pilih Bulan',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(12, (i) {
                  final monthIdx = i + 1;
                  final isSelected = monthIdx == _selectedMonthIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMonthIndex = monthIdx;
                        final maxDay = _daysInMonth(_selectedYear, _selectedMonthIndex);
                        if (_selectedDay != null && _selectedDay! > maxDay) {
                          _selectedDay = maxDay;
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 90,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.borderLight,
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _getMonthName(monthIdx),
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // ── Day Picker ──
  void _pickDay() async {
    final result = await showDialog(
      context: context,
      builder: (ctx) => _DayPickerFilterDialog(
        initialYear: _selectedYear,
        initialMonth: _selectedMonthIndex,
        initialDay: _selectedDay,
      ),
    );

    if (result == 'delete') {
      setState(() {
        _selectedDay = null;
      });
    } else if (result is DateTime) {
      setState(() {
        _selectedYear = result.year;
        _selectedMonthIndex = result.month;
        _selectedDay = result.day;
      });
    }
  }

  // ── Sort By Popup ──
  void _showSortByMenu() {
    final categories = ['Semua', 'Surat Keluar', 'Nota Dinas', 'Surat Keputusan'];
    final RenderBox button = context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        button.size.width - 180,
        260,
        20,
        0,
      ),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.borderLight),
      ),
      items: categories.map((cat) {
        final isSelected = _sortCategory == cat;
        return PopupMenuItem<String>(
          value: cat,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                cat,
                style: TextStyle(
                  color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        setState(() {
          _sortCategory = value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.user;
        if (user == null) return const SizedBox.shrink();

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppTheme.surfaceAlt,
          // ── Drawer (Hamburger Menu) ──
          drawer: _buildDrawer(context, auth, user.namaLengkapDisplay, user.singkatanDisplay, user.isAdmin),
          bottomNavigationBar: _buildAdminBottomNav(user.roleDisplay),
          body: Container(
            color: AppTheme.primaryDark,
            child: SafeArea(
              bottom: false,
              child: Container(
                color: AppTheme.surfaceAlt,
                child: Column(
                  children: [
                    // === TOP HEADER SECTION WITH BIG + BUTTON / ADMIN BANNER ===
                    _buildHeaderSection(context, user.namaLengkapDisplay, user.singkatanDisplay, user.isAdmin),

                    const SizedBox(height: 14),

                    // === SCROLLABLE CONTENT SECTION ===
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // 1. THREE DATE SELECTOR PILLS (Tahun, Bulan, Tanggal) — tappable
                          Row(
                            children: [
                              Expanded(
                                child: _buildDatePill(
                                  '$_selectedYear',
                                  onTap: _pickYear,
                                  icon: Icons.calendar_today_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDatePill(
                                  _getMonthName(_selectedMonthIndex),
                                  onTap: _pickMonth,
                                  icon: Icons.date_range_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDatePill(
                                  _selectedDay == null ? 'Semua' : '$_selectedDay',
                                  onTap: _pickDay,
                                  icon: Icons.today_rounded,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // 2. SEARCH BAR + SORT BY BUTTON
                          Row(
                            children: [
                              // Search Bar
                              Expanded(
                                flex: 6,
                                child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: AppTheme.borderLight),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.search, size: 20, color: AppTheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            hintText: 'Cari perihal, nomor, nama...',
                                            hintStyle: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {
                                            _showSuggestions = _searchController.text.isNotEmpty;
                                          }),
                                          onTap: () => setState(() {
                                            _showSuggestions = _searchController.text.isNotEmpty;
                                          }),
                                        ),
                                      ),
                                      if (_searchController.text.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _searchController.clear();
                                              _showSuggestions = false;
                                            });
                                          },
                                          child: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              // Sort By Button — clickable with category popup
                              Expanded(
                                flex: 4,
                                child: GestureDetector(
                                  onTap: _showSortByMenu,
                                  child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _sortCategory != 'Semua'
                                          ? AppTheme.primary
                                          : AppTheme.surface,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: _sortCategory != 'Semua'
                                            ? AppTheme.primary
                                            : AppTheme.borderLight,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.filter_list_rounded,
                                          size: 18,
                                          color: _sortCategory != 'Semua'
                                              ? Colors.white
                                              : AppTheme.textPrimary,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            _sortCategory != 'Semua'
                                                ? _sortCategory
                                                : 'sort by',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _sortCategory != 'Semua'
                                                  ? Colors.white
                                                  : AppTheme.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 18,
                                          color: _sortCategory != 'Semua'
                                              ? Colors.white70
                                              : AppTheme.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Search suggestions dropdown
                          if (_showSuggestions && _getSuggestions().isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderLight, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _getSuggestions().map((suggestion) {
                                  final query = _searchController.text.toLowerCase();
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _searchController.text = suggestion;
                                        _searchController.selection = TextSelection.fromPosition(
                                          TextPosition(offset: suggestion.length),
                                        );
                                        _showSuggestions = false;
                                        _searchFocusNode.unfocus();
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.search, size: 14, color: AppTheme.primary),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _buildHighlightedSuggestion(suggestion, query),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                          const SizedBox(height: 16),

                          // Header for available numbers
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _searchController.text.trim().isNotEmpty
                                      ? 'Hasil pencarian ("${_searchController.text.trim()}")'
                                      : (user.roleDisplay == 'Admin'
                                          ? (_adminTabIndex == 0
                                              ? (_selectedDay == null
                                                  ? 'Surat belum ACC (bulan ${_getMonthName(_selectedMonthIndex)} $_selectedYear)'
                                                  : 'Surat belum ACC ($_selectedDay ${_getMonthName(_selectedMonthIndex)} $_selectedYear)')
                                              : (_selectedDay == null
                                                  ? 'Surat sudah ACC (bulan ${_getMonthName(_selectedMonthIndex)} $_selectedYear)'
                                                  : 'Surat sudah ACC ($_selectedDay ${_getMonthName(_selectedMonthIndex)} $_selectedYear)'))
                                          : (_selectedDay == null
                                              ? 'Surat bulan ${_getMonthName(_selectedMonthIndex)} $_selectedYear'
                                              : 'Surat tanggal $_selectedDay ${_getMonthName(_selectedMonthIndex)} $_selectedYear')),
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (_isLoadingRealData)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                )
                              else
                                InkWell(
                                  onTap: _fetchRealAgendaNumbers,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Row(
                                      children: const [
                                        Icon(Icons.refresh, size: 14, color: AppTheme.primary),
                                        SizedBox(width: 4),
                                        Text(
                                          'Refresh',
                                          style: TextStyle(
                                            color: AppTheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 3. FILTERED LIST OF REAL AGENDA NUMBERS
                          if (_realAgendaList.isNotEmpty) ...[
                            ..._getFilteredRealData(user.roleDisplay).map((agenda) => _RealAgendaCard(
                                  agenda: agenda,
                                  searchQuery: _searchController.text.trim(),
                                  isAdmin: user.roleDisplay == 'Admin',
                                  isHighlighted: agenda.id == _highlightedAgendaId,
                                  onStatusChanged: _fetchRealAgendaNumbers,
                                )),
                            if (_getFilteredRealData(user.roleDisplay).isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(36),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.cardBorder),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      _searchController.text.trim().isNotEmpty
                                          ? Icons.search_off_rounded
                                          : Icons.event_busy_rounded,
                                      size: 44,
                                      color: AppTheme.primaryLight,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchController.text.trim().isNotEmpty
                                          ? 'Tidak ada surat ditemukan'
                                          : (_selectedDay == null
                                              ? 'Tidak ada surat agenda pada bulan ${_getMonthName(_selectedMonthIndex)} $_selectedYear'
                                              : 'Tidak ada surat agenda pada tanggal $_selectedDay ${_getMonthName(_selectedMonthIndex)} $_selectedYear'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                                    ),
                                    if (_searchController.text.trim().isEmpty) ...[
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Gunakan tombol + untuk membuat nomor agenda baru',
                                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ] else ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(36),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.cardBorder),
                              ),
                              child: Column(
                                children: const [
                                  Icon(Icons.assignment_outlined, size: 44, color: AppTheme.primaryLight),
                                  SizedBox(height: 12),
                                  Text(
                                    'Belum ada nomor agenda yang dibuat',
                                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Tekan tombol + di atas untuk membuat nomor agenda baru',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

  /// Drawer for hamburger menu — contains user info, settings, logout
  Widget _buildDrawer(BuildContext context, AuthProvider auth, String namaLengkap, String singkatan, bool isAdmin) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header — user info with primary gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryDark, AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User avatar
                  CircleAvatar(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    radius: 28,
                    child: Icon(
                      isAdmin
                          ? Icons.admin_panel_settings_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    namaLengkap,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Login sebagai $singkatan',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Menu Items
            _buildDrawerItem(
              icon: Icons.home_rounded,
              label: 'Beranda',
              isActive: true,
              onTap: () => Navigator.pop(context),
            ),
            _buildDrawerItem(
              icon: Icons.history_rounded,
              label: 'Riwayat Surat',
              onTap: () => Navigator.pop(context),
            ),
            if (isAdmin)
              _buildDrawerItem(
                icon: Icons.tune_rounded,
                label: 'Pengaturan Limit Agenda',
                onTap: () {
                  _openBufferSettingsDialog(context, true);
                },
              ),
            _buildDrawerItem(
              icon: Icons.system_update_alt_rounded,
              label: 'Cek Pembaruan',
              onTap: () {
                Navigator.pop(context);
                _checkManualUpdate(context);
              },
            ),
            _buildDrawerItem(
              icon: Icons.info_outline_rounded,
              label: 'Tentang MONA',
              onTap: () => Navigator.pop(context),
            ),

            const Spacer(),

            // Logout Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    auth.logout();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _checkManualUpdate(BuildContext context) async {
    final updateService = UpdateService();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Memeriksa pembaruan versi...'),
        duration: Duration(seconds: 1),
      ),
    );

    final results = await Future.wait([
      updateService.checkLatestVersion(),
      updateService.getCurrentPackageInfo(),
    ]);

    final latest = results[0] as dynamic;
    final packageInfo = results[1] as dynamic;

    if (!context.mounted) return;

    if (latest != null) {
      final currentCode = int.tryParse(packageInfo.buildNumber.toString()) ?? 1;
      if (latest.hasUpdate(currentCode)) {
        await showUpdateDialog(
          context,
          version: latest,
          currentVersionCode: currentCode,
        );
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Aplikasi sudah versi terbaru (v${packageInfo.version})'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openBufferSettingsDialog(BuildContext context, bool isAdmin) {
    if (Navigator.of(context).canPop() && _scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context); // Close drawer if opened from drawer
    }
    showDialog(
      context: context,
      builder: (ctx) => _BufferSettingsDialog(isAdmin: isAdmin),
    );
  }

  /// Single drawer menu item
  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? AppTheme.primary : AppTheme.textSecondary,
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? AppTheme.primary : AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: isActive ? AppTheme.surfaceAlt : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: onTap,
    );
  }

  /// Top Header Section with MONA Branding, Menu, Role & Floating + Button / Admin Card
  Widget _buildHeaderSection(BuildContext context, String namaLengkap, String singkatan, bool isAdmin) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              children: [
                // Top Header Row: Hamburger + MONA Branding + Notification + Role Badge
                Row(
                  children: [
                    // Hamburger menu icon — opens the drawer
                    GestureDetector(
                      onTap: () {
                        _scaffoldKey.currentState?.openDrawer();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.menu_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // MONA branding logo container
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/app_logo.jpeg',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.mark_email_read_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'MONA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Text(
                            'Diskominfo Kota Malang',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Notification Bell Icon + Badge
                    _buildNotificationBellIcon(),
                    const SizedBox(width: 6),

                    // Role Badge (e.g. "Aptika", "Sandi Kami", "Admin")
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        singkatan,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Operator: Big Central White + Button | Admin: Single Top Card "Pengaturan Limit Agenda"
                if (!isAdmin) ...[
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.of(context).pushNamed('/form-agenda');
                        _fetchRealAgendaNumbers();
                      },
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 46,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  // Single prominent Admin button / card
                  GestureDetector(
                    onTap: () => _openBufferSettingsDialog(context, true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Pengaturan Limit Agenda',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Atur jumlah buffer nomor cadangan otomatis & cadangan tanggal',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Notification Bell Icon with dynamic unread badge
  Widget _buildNotificationBellIcon() {
    return StreamBuilder<List<NotificationModel>>(
      stream: NotificationService().streamNotifications(),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final unreadCount = notifications.where((n) => !n.isRead).length;

        return GestureDetector(
          onTap: () => _showNotificationSheet(context, notifications),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Bottom Sheet displaying Notifications list
  void _showNotificationSheet(BuildContext context, List<NotificationModel> notifications) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          expand: false,
          builder: (_, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return Container(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.notifications_rounded, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Text(
                                'Notifikasi',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (notifications.any((n) => !n.isRead))
                            TextButton(
                              onPressed: () async {
                                await NotificationService().markAllAsRead();
                                setSheetState(() {});
                              },
                              child: const Text(
                                'Tandai Semua Dibaca',
                                style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const Divider(color: AppTheme.borderLight),
                      Expanded(
                        child: notifications.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.notifications_none_rounded, size: 48, color: AppTheme.primaryLight),
                                    SizedBox(height: 12),
                                    Text(
                                      'Belum ada notifikasi',
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: notifications.length,
                                separatorBuilder: (ctx, index) => const Divider(color: AppTheme.borderLight, height: 1),
                                itemBuilder: (context, index) {
                                  final n = notifications[index];
                                  return ListTile(
                                    tileColor: n.isRead ? null : AppTheme.surfaceAlt.withValues(alpha: 0.6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    leading: CircleAvatar(
                                      backgroundColor: n.tipe == 'acc'
                                          ? AppTheme.success.withValues(alpha: 0.15)
                                          : n.tipe == 'tolak'
                                              ? AppTheme.danger.withValues(alpha: 0.15)
                                              : AppTheme.primary.withValues(alpha: 0.15),
                                      child: Icon(
                                        n.tipe == 'acc'
                                            ? Icons.check_circle_outline_rounded
                                            : n.tipe == 'tolak'
                                                ? Icons.cancel_outlined
                                                : Icons.assignment_outlined,
                                        color: n.tipe == 'acc'
                                            ? AppTheme.success
                                            : n.tipe == 'tolak'
                                                ? AppTheme.danger
                                                : AppTheme.primary,
                                      ),
                                    ),
                                    title: Text(
                                      n.judul,
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: n.isRead ? FontWeight.w500 : FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          n.isi,
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year} ${n.createdAt.hour.toString().padLeft(2, '0')}:${n.createdAt.minute.toString().padLeft(2, '0')}',
                                          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.7), fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      await NotificationService().markAsRead(n.id);
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      if (n.agendaId != null) {
                                        _searchController.text = '${n.agendaId}';
                                        _fetchRealAgendaNumbers();
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// White Pill Box for Date Selector (Tahun, Bulan, Tanggal) — tappable
  Widget _buildDatePill(String text, {required VoidCallback onTap, required IconData icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderLight),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom Navigation Bar specifically for Admin
  Widget? _buildAdminBottomNav(String role) {
    if (role != 'Admin') return null;

    return BottomNavigationBar(
      backgroundColor: AppTheme.surface,
      selectedItemColor: AppTheme.primary,
      unselectedItemColor: AppTheme.textSecondary,
      currentIndex: _adminTabIndex.clamp(0, 1),
      onTap: (index) {
        setState(() {
          _adminTabIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.pending_actions_rounded),
          label: 'Belum ACC',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.check_circle_rounded),
          label: 'Sudah ACC',
        ),
      ],
    );
  }

  /// Build a suggestion text with the query portion highlighted
  Widget _buildHighlightedSuggestion(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: TextStyle(color: Colors.grey.shade300, fontSize: 12));
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);
    if (matchIndex == -1) {
      return Text(text, style: TextStyle(color: Colors.grey.shade300, fontSize: 12));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + query.length),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: text.substring(matchIndex + query.length)),
        ],
      ),
    );
  }
}


class _RealAgendaCard extends StatefulWidget {
  final AgendaNumberModel agenda;
  final String searchQuery;
  final bool isAdmin;
  final bool isHighlighted;
  final VoidCallback? onStatusChanged;

  const _RealAgendaCard({
    required this.agenda,
    this.searchQuery = '',
    this.isAdmin = false,
    this.isHighlighted = false,
    this.onStatusChanged,
  });

  @override
  State<_RealAgendaCard> createState() => _RealAgendaCardState();
}

class _RealAgendaCardState extends State<_RealAgendaCard> {
  late bool _isExpanded;
  bool _isProcessing = false;
  final _agendaService = AgendaService();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isHighlighted;
  }

  Color get _statusColor {
    switch (widget.agenda.statusAcc) {
      case 'menunggu':
        return Colors.orange.shade700;
      case 'disetujui':
        return Colors.green.shade600;
      case 'ditolak':
        return Colors.red.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  Color get _statusBgColor {
    switch (widget.agenda.statusAcc) {
      case 'menunggu':
        return Colors.orange.shade900.withValues(alpha: 0.15);
      case 'disetujui':
        return Colors.green.shade900.withValues(alpha: 0.15);
      case 'ditolak':
        return Colors.red.shade900.withValues(alpha: 0.15);
      default:
        return Colors.orange.shade900.withValues(alpha: 0.15);
    }
  }

  Color get _statusTextColor {
    switch (widget.agenda.statusAcc) {
      case 'menunggu':
        return Colors.orange.shade700;
      case 'disetujui':
        return Colors.green.shade700;
      case 'ditolak':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.agenda.nomorLengkap));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nomor agenda disalin: ${widget.agenda.nomorLengkap}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEditDraft() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditAgendaDialog(
        agenda: widget.agenda,
        onSaved: () {
          widget.onStatusChanged?.call();
        },
      ),
    );
  }

  Future<void> _handleApprove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Setujui Pengajuan', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Apakah Anda yakin ingin menyetujui nomor agenda ${widget.agenda.nomorLengkap}?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Setujui'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      await _agendaService.approveAgenda(widget.agenda.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nomor agenda ${widget.agenda.nomorLengkap} berhasil disetujui!'),
            backgroundColor: AppTheme.success,
          ),
        );
        widget.onStatusChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyetujui: $msg'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Tolak Pengajuan', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tolak pengajuan nomor agenda ${widget.agenda.nomorLengkap}?',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteController,
              maxLines: 3,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Alasan / Catatan Penolakan (opsional)',
                hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.danger),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tolak Pengajuan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      await _agendaService.rejectAgenda(
        widget.agenda.id,
        catatan: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nomor agenda ${widget.agenda.nomorLengkap} telah ditolak.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        widget.onStatusChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menolak: $msg'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isHighlighted ? AppTheme.primary : AppTheme.cardBorder,
          width: widget.isHighlighted ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isHighlighted
                ? AppTheme.primary.withValues(alpha: 0.18)
                : AppTheme.primary.withValues(alpha: 0.04),
            blurRadius: widget.isHighlighted ? 14 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable header
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // Status Strip Indicator
                            Container(
                              width: 8,
                              height: 18,
                              decoration: BoxDecoration(
                                color: _statusColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Category Display Name
                            Flexible(
                              child: _highlightText(
                                widget.agenda.kategoriDisplay,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _statusBgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _statusColor.withValues(alpha: 0.5), width: 0.8),
                              ),
                              child: Text(
                                widget.agenda.statusDisplay,
                                style: TextStyle(
                                  color: _statusTextColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _highlightText(
                            widget.agenda.pemohon,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _buildHighlightedAgendaNumber()),
                      IconButton(
                        tooltip: 'Salin Nomor Agenda',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.content_copy_rounded, size: 18, color: AppTheme.primary),
                        onPressed: _copyToClipboard,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expandable body
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_isExpanded
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1, color: AppTheme.borderLight),
                        const SizedBox(height: 12),
                        _buildDetailRow('Kode Klasifikasi', widget.agenda.kodeKlasifikasi),
                        _buildDetailRow('Perihal', widget.agenda.perihal),
                        _buildDetailRow('Tujuan Surat', widget.agenda.tujuanSurat),
                        _buildDetailRow('Tanggal Agenda', widget.agenda.tanggalAgenda),
                        _buildDetailRow('Status ACC', widget.agenda.statusDisplay),
                        if (widget.agenda.catatanAdmin != null && widget.agenda.catatanAdmin!.isNotEmpty)
                          _buildDetailRow('Catatan Admin', widget.agenda.catatanAdmin!),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Tanggal Dibuat: ${widget.agenda.tanggalDibuatDisplay}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),

                        // Action Buttons: Edit Draft (sebelum ACC) & Admin Actions
                        if (widget.agenda.statusAcc == 'menunggu') ...[
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: AppTheme.borderLight),
                          const SizedBox(height: 12),
                          if (_isProcessing)
                            const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                              ),
                            )
                          else if (widget.isAdmin)
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.danger,
                                          side: const BorderSide(color: AppTheme.danger, width: 1.2),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                                        ),
                                        icon: const Icon(Icons.close_rounded, size: 16),
                                        label: const Text(
                                          'Tolak',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onPressed: _handleReject,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.success,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                                        ),
                                        icon: const Icon(Icons.check_rounded, size: 16),
                                        label: const Text(
                                          'Setujui (ACC)',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onPressed: _handleApprove,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primary,
                                      side: const BorderSide(color: AppTheme.borderLight, width: 1.2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    ),
                                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                                    label: const Text(
                                      'Edit Data',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                    onPressed: _handleEditDraft,
                                  ),
                                ),
                              ],
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: const BorderSide(color: AppTheme.primary, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                ),
                                icon: const Icon(Icons.edit_note_rounded, size: 18),
                                label: const Text(
                                  'Edit Data',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                ),
                                onPressed: _handleEditDraft,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Highlight & enlarge the agenda sequence number (e.g. "12") for fast scanning
  Widget _buildHighlightedAgendaNumber() {
    final full = widget.agenda.nomorLengkap;
    final parts = full.split('/');

    if (parts.length >= 3) {
      final prefix = parts[0].trim();
      final nomorAgenda = parts[1].trim();
      final rest = parts.sublist(2).map((p) => p.trim()).join(' / ');

      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _highlightText(
            '$prefix / ',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primary, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _highlightText(
              nomorAgenda,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _highlightText(
            ' / $rest',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return _highlightText(
      full,
      style: const TextStyle(
        color: AppTheme.primaryDark,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  /// Highlight matching search query in yellow
  Widget _highlightText(String text, {required TextStyle style}) {
    final query = widget.searchQuery.toLowerCase().trim();
    if (query.isEmpty) {
      return Text(text, style: style);
    }
    final lowerText = text.toLowerCase();
    final matchIndex = lowerText.indexOf(query);
    if (matchIndex == -1) {
      return Text(text, style: style);
    }
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + query.length),
            style: style.copyWith(
              backgroundColor: Colors.yellow.shade300,
              color: Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: text.substring(matchIndex + query.length)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
          Expanded(
            child: _highlightText(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for Editing Agenda Details before ACC (Status Menunggu)
class _EditAgendaDialog extends StatefulWidget {
  final AgendaNumberModel agenda;
  final VoidCallback onSaved;

  const _EditAgendaDialog({
    required this.agenda,
    required this.onSaved,
  });

  @override
  State<_EditAgendaDialog> createState() => _EditAgendaDialogState();
}

class _EditAgendaDialogState extends State<_EditAgendaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _agendaService = AgendaService();

  late final TextEditingController _kodeController;
  late final TextEditingController _tujuanController;
  late final TextEditingController _perihalController;
  late final TextEditingController _pemohonController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _kodeController = TextEditingController(text: widget.agenda.kodeKlasifikasi);
    _tujuanController = TextEditingController(text: widget.agenda.tujuanSurat);
    _perihalController = TextEditingController(text: widget.agenda.perihal);
    _pemohonController = TextEditingController(text: widget.agenda.pemohon);
  }

  @override
  void dispose() {
    _kodeController.dispose();
    _tujuanController.dispose();
    _perihalController.dispose();
    _pemohonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await _agendaService.updateAgendaDraft(
        id: widget.agenda.id,
        kodeKlasifikasi: _kodeController.text.trim(),
        tujuanSurat: _tujuanController.text.trim(),
        perihal: _perihalController.text.trim(),
        pemohon: _pemohonController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft nomor agenda berhasil diperbarui!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui: $msg'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.edit_note_rounded, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Edit Data Agenda',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Readonly Info: Locked Nomor & Tanggal
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'Nomor & Tanggal Terkunci (Permanen)',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.agenda.nomorLengkap,
                        style: const TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Kategori: ${widget.agenda.kategoriDisplay} • Tanggal: ${widget.agenda.tanggalAgenda}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Kode Klasifikasi
                _buildInputField(
                  controller: _kodeController,
                  label: 'Kode Klasifikasi',
                  hint: 'Contoh: 500.12.8.2',
                  icon: Icons.tag_rounded,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),

                // Tujuan Surat
                _buildInputField(
                  controller: _tujuanController,
                  label: 'Tujuan Surat',
                  hint: 'Contoh: Kepala Dinas Kominfo',
                  icon: Icons.send_rounded,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),

                // Perihal
                _buildInputField(
                  controller: _perihalController,
                  label: 'Perihal',
                  hint: 'Perihal / uraian surat',
                  icon: Icons.subject_rounded,
                  maxLines: 2,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 12),

                // Pemohon
                _buildInputField(
                  controller: _pemohonController,
                  label: 'Pemohon / User Bidang',
                  hint: 'Nama pemohon atau bidang pengaju',
                  icon: Icons.person_rounded,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Simpan Perubahan'),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            prefixIcon: Icon(icon, color: AppTheme.primary, size: 18),
            filled: true,
            fillColor: AppTheme.surfaceAlt,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom Dialog for picking a date filter with Delete / Clear button alongside Cancel & OK
class _DayPickerFilterDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final int? initialDay;

  const _DayPickerFilterDialog({
    required this.initialYear,
    required this.initialMonth,
    required this.initialDay,
  });

  @override
  State<_DayPickerFilterDialog> createState() => _DayPickerFilterDialogState();
}

class _DayPickerFilterDialogState extends State<_DayPickerFilterDialog> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDay ?? 1;
    final maxDayInMonth = DateTime(widget.initialYear, widget.initialMonth + 1, 0).day;
    final validDay = day > maxDayInMonth ? maxDayInMonth : day;
    _selectedDate = DateTime(widget.initialYear, widget.initialMonth, validDay);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(
          primary: AppTheme.primary,
          onPrimary: Colors.white,
          surface: AppTheme.surface,
          onSurface: AppTheme.textPrimary,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppTheme.surface,
        ),
      ),
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SizedBox(
          width: 320,
          height: 330,
          child: CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2035, 12, 31),
            onDateChanged: (DateTime date) {
              setState(() {
                _selectedDate = date;
              });
            },
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                ),
                child: const Text('Cancel'),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop('delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selectedDate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Overhauled Single-View Buffer Limit Dialog for Admin
class _BufferSettingsDialog extends StatefulWidget {
  final bool isAdmin;
  const _BufferSettingsDialog({required this.isAdmin});

  @override
  State<_BufferSettingsDialog> createState() => _BufferSettingsDialogState();
}

class _BufferSettingsDialogState extends State<_BufferSettingsDialog> {
  final _agendaService = AgendaService();
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<String, int> _bufferCounts = {
    'surat_keluar': 5,
    'nota_dinas': 5,
    'surat_keputusan': 5,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _agendaService.getBufferSettings();
      if (mounted) {
        setState(() {
          for (final s in settings) {
            final cat = s['kategori'] as String?;
            final count = s['jumlah_buffer'] as int?;
            if (cat != null && count != null) {
              _bufferCounts[cat] = count;
            }
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resetToDefault() {
    setState(() {
      _bufferCounts['surat_keluar'] = 5;
      _bufferCounts['nota_dinas'] = 5;
      _bufferCounts['surat_keputusan'] = 5;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nilai limit dikembalikan ke default (5)'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!widget.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('FORBIDDEN: Hanya Admin yang dapat mengubah limit agenda'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      for (final entry in _bufferCounts.entries) {
        await _agendaService.updateBufferSetting(entry.key, entry.value);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengaturan limit nomor cadangan berhasil disimpan!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Atur Limit Nomor Agenda',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tentukan kuota nomor cadangan otomatis untuk kebutuhan tanggal lampau (backdate).',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: _isLoading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Informative Banner
                    Container(
                      padding: const EdgeInsets.all(9),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Jika tidak diubah, sistem otomatis menggunakan default 5 nomor cadangan per periode.',
                              style: TextStyle(color: AppTheme.primaryDark, fontSize: 10.5, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 1. Surat Keluar (Harian)
                    _buildCategoryCard(
                      title: 'Surat Keluar',
                      keyName: 'surat_keluar',
                      badgeText: 'Harian',
                      badgeColor: Colors.blue.shade700,
                      badgeBgColor: Colors.blue.shade50,
                      desc: 'Cadangan otomatis dialokasikan setiap hari pukul 00:00 WIB',
                    ),
                    const SizedBox(height: 8),

                    // 2. Nota Dinas (Bulanan)
                    _buildCategoryCard(
                      title: 'Nota Dinas',
                      keyName: 'nota_dinas',
                      badgeText: 'Bulanan',
                      badgeColor: Colors.purple.shade700,
                      badgeBgColor: Colors.purple.shade50,
                      desc: 'Cadangan otomatis dialokasikan setiap awal bulan',
                    ),
                    const SizedBox(height: 8),

                    // 3. Surat Keputusan (Bulanan)
                    _buildCategoryCard(
                      title: 'Surat Keputusan (SK)',
                      keyName: 'surat_keputusan',
                      badgeText: 'Bulanan',
                      badgeColor: Colors.teal.shade700,
                      badgeBgColor: Colors.teal.shade50,
                      desc: 'Cadangan otomatis dialokasikan setiap awal bulan',
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _isLoading || _isSaving ? null : _resetToDefault,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              child: const Text('Reset ke 5', style: TextStyle(fontSize: 11.5)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Tutup', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                if (widget.isAdmin)
                  ElevatedButton(
                    onPressed: _isLoading || _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Simpan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String keyName,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBgColor,
    required String desc,
  }) {
    final count = _bufferCounts[keyName] ?? 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: badgeBgColor,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Stepper Controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primary, size: 20),
                    onPressed: widget.isAdmin && count > 1
                        ? () => setState(() => _bufferCounts[keyName] = count - 1)
                        : null,
                  ),
                  InkWell(
                    onTap: widget.isAdmin ? () => _showManualNumberInput(title, keyName, count) : null,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppTheme.borderLight, width: 1.1),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 20),
                    onPressed: widget.isAdmin && count < 99
                        ? () => setState(() => _bufferCounts[keyName] = count + 1)
                        : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            desc,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  void _showManualNumberInput(String title, String keyName, int currentVal) {
    final controller = TextEditingController(text: currentVal.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ubah Limit $title', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Masukkan jumlah nomor',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val >= 1) {
                setState(() => _bufferCounts[keyName] = val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
  }
}



