import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Popup "Pilih Tanggal" — matching 05-popup-pilih-tanggal.png
///
/// Shows a calendar for picking a PAST date (backdate only).
/// Returns the selected DateTime, or null if cancelled.
Future<DateTime?> showPopupPilihTanggal(BuildContext context) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => const _PilihTanggalDialog(),
  );
}

class _PilihTanggalDialog extends StatefulWidget {
  const _PilihTanggalDialog();

  @override
  State<_PilihTanggalDialog> createState() => _PilihTanggalDialogState();
}

class _PilihTanggalDialogState extends State<_PilihTanggalDialog> {
  late DateTime _currentMonth;
  DateTime? _selectedDate;
  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Start showing the current month
    _currentMonth = DateTime(_today.year, _today.month, 1);
  }

  /// Get days to display in the calendar grid
  List<DateTime?> _getCalendarDays() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = lastDay.day;

    // Sunday = 0, Monday = 1, ...
    // Adjust: firstDay.weekday (Monday=1, Sunday=7) → we want Sunday=0
    int startWeekday = firstDay.weekday % 7; // Sunday=0, Monday=1, ...

    final List<DateTime?> days = [];

    // Empty slots before the first day
    for (int i = 0; i < startWeekday; i++) {
      days.add(null);
    }

    // Days of the month
    for (int d = 1; d <= daysInMonth; d++) {
      days.add(DateTime(_currentMonth.year, _currentMonth.month, d));
    }

    return days;
  }

  bool _isSelectable(DateTime date) {
    // Only past dates are selectable (before today)
    return date.isBefore(DateTime(_today.year, _today.month, _today.day));
  }

  bool _isSelected(DateTime date) {
    if (_selectedDate == null) return false;
    return date.year == _selectedDate!.year &&
        date.month == _selectedDate!.month &&
        date.day == _selectedDate!.day;
  }

  bool _isToday(DateTime date) {
    return date.year == _today.year &&
        date.month == _today.month &&
        date.day == _today.day;
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  static const _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  static const _dayHeaders = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    final calendarDays = _getCalendarDays();
    final monthLabel = '${_monthNames[_currentMonth.month - 1]} ${_currentMonth.year}';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                const Text(
                  'Pilih Tanggal',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),

                // Month navigation
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 22),
                      onPressed: _prevMonth,
                      splashRadius: 18,
                      color: Colors.black54,
                    ),
                    Text(
                      monthLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 22),
                      onPressed: _nextMonth,
                      splashRadius: 18,
                      color: Colors.black54,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Day-of-week headers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _dayHeaders
                      .map((d) => SizedBox(
                            width: 36,
                            child: Center(
                              child: Text(
                                d,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: d == 'Su'
                                      ? Colors.red.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),

                // Calendar grid
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.1,
                  children: calendarDays.map((date) {
                    if (date == null) {
                      return const SizedBox.shrink();
                    }

                    final selectable = _isSelectable(date);
                    final selected = _isSelected(date);
                    final today = _isToday(date);
                    final isSunday = date.weekday == DateTime.sunday;

                    return GestureDetector(
                      onTap: selectable
                          ? () {
                              setState(() {
                                _selectedDate = date;
                              });
                            }
                          : null,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : today
                                  ? AppTheme.surfaceAlt
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected || today
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: selected
                                  ? Colors.white
                                  : !selectable
                                      ? Colors.grey.shade300
                                      : isSunday
                                          ? Colors.red.shade400
                                          : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // OKE button
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _selectedDate != null
                        ? () => Navigator.of(context).pop(_selectedDate)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: _selectedDate != null ? 2 : 0,
                    ),
                    child: const Text(
                      'OKE',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
