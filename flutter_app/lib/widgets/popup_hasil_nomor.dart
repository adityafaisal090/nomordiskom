import 'package:flutter/material.dart';

/// Popup Hasil Nomor — matching 06-popup-hasil-nomor.png
///
/// Two variants:
/// - SUCCESS: "Anda mendapatkan nomor surat" + nomor lengkap + green checkmark
/// - ERROR: "Nomor Agenda Untuk Tanggal Tersebut Sudah Habis..." + red X
///
/// Returns when user dismisses the popup.
Future<void> showPopupHasilNomor(
  BuildContext context, {
  required bool isSuccess,
  String? nomorLengkap,
  String? errorMessage,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => _HasilNomorDialog(
      isSuccess: isSuccess,
      nomorLengkap: nomorLengkap,
      errorMessage: errorMessage,
    ),
  );
}

class _HasilNomorDialog extends StatelessWidget {
  final bool isSuccess;
  final String? nomorLengkap;
  final String? errorMessage;

  const _HasilNomorDialog({
    required this.isSuccess,
    this.nomorLengkap,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 36),
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
            child: isSuccess ? _buildSuccess(context) : _buildError(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        const Text(
          'Anda mendapatkan nomor surat',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),

        // Nomor lengkap
        Text(
          nomorLengkap ?? '-',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 20),

        // Green checkmark icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.green.shade500,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 20),

        // Close / OK button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Text(
            'Tutup',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error message
        Text(
          errorMessage ??
              'Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        // Red X icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.red.shade500,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.close,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),

        // "Kembali ke halaman sebelumnya"
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Text(
            'Kembali ke halaman sebelumnya',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
