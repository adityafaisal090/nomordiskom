import 'package:flutter/material.dart';

/// Popup "Ingin Membuat Nomor Surat Untuk Kapan?" — matching 04-popup-pilih-waktu.png
///
/// Returns:
///   - 'hari_ini' if user picks "Hari Ini"
///   - 'hari_lain' if user picks "Hari Lain"
///   - null if user picks "Kembali" or dismisses
Future<String?> showPopupPilihWaktu(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => const _PilihWaktuDialog(),
  );
}

class _PilihWaktuDialog extends StatelessWidget {
  const _PilihWaktuDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 40),
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
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                const Text(
                  'Ingin Membuat Nomor Surat\nUntuk Kapan?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 24),

                // Option: Hari Ini
                _OptionItem(
                  label: 'Hari Ini',
                  onTap: () => Navigator.of(context).pop('hari_ini'),
                ),
                const SizedBox(height: 6),

                // Divider
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 6),

                // Option: Hari Lain
                _OptionItem(
                  label: 'Hari Lain',
                  onTap: () => Navigator.of(context).pop('hari_lain'),
                ),
                const SizedBox(height: 6),

                // Divider
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 6),

                // Option: Kembali
                _OptionItem(
                  label: 'Kembali',
                  onTap: () => Navigator.of(context).pop(null),
                  isSecondary: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSecondary;

  const _OptionItem({
    required this.label,
    required this.onTap,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isSecondary ? FontWeight.w400 : FontWeight.w500,
              color: isSecondary ? Colors.grey.shade600 : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
