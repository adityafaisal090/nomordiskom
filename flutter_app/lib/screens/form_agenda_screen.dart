import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/agenda_service.dart';
import '../widgets/popup_pilih_waktu.dart';
import '../widgets/popup_pilih_tanggal.dart';
import '../widgets/popup_hasil_nomor.dart';
import '../theme/app_theme.dart';

/// Form Buat Nomor Agenda — matching MONA Blue+White theme (design.md 9.1)
///
/// Light blue-tinted background, pill-shaped inputs with blue accents.
/// Fields: Kategori (dropdown), Kode Klasifikasi, Perihal, Tujuan Surat, Pemohon.
/// Validates all fields before enabling BUAT button.
/// Flow: BUAT → Popup Pilih Waktu → (Hari Ini | Hari Lain→Calendar) → Popup Hasil
class FormAgendaScreen extends StatefulWidget {
  const FormAgendaScreen({super.key});

  @override
  State<FormAgendaScreen> createState() => _FormAgendaScreenState();
}

class _FormAgendaScreenState extends State<FormAgendaScreen> {
  final _agendaService = AgendaService();

  // Form controllers
  String? _selectedKategori;
  final _kodeKlasifikasiController = TextEditingController();
  final _perihalController = TextEditingController();
  final _tujuanSuratController = TextEditingController();
  final _pemohonController = TextEditingController();

  bool _isLoading = false;

  // Kategori options
  static const _kategoriOptions = [
    {'value': 'surat_keputusan', 'label': 'Surat Keputusan'},
    {'value': 'nota_dinas', 'label': 'Nota Dinas'},
    {'value': 'surat_keluar', 'label': 'Surat Keluar'},
  ];

  @override
  void dispose() {
    _kodeKlasifikasiController.dispose();
    _perihalController.dispose();
    _tujuanSuratController.dispose();
    _pemohonController.dispose();
    super.dispose();
  }

  /// Check if all fields are filled
  bool get _isFormValid {
    return _selectedKategori != null &&
        _selectedKategori!.isNotEmpty &&
        _kodeKlasifikasiController.text.trim().isNotEmpty &&
        _perihalController.text.trim().isNotEmpty &&
        _tujuanSuratController.text.trim().isNotEmpty &&
        _pemohonController.text.trim().isNotEmpty;
  }

  /// Main flow: BUAT button pressed
  Future<void> _onBuatPressed() async {
    if (!_isFormValid) {
      _showSnackBar('Semua field wajib diisi sebelum membuat nomor agenda.');
      return;
    }

    // Step 1: Show popup pilih waktu
    final waktu = await showPopupPilihWaktu(context);
    if (waktu == null || !mounted) return; // User chose "Kembali"

    if (waktu == 'hari_ini') {
      await _issueHariIni();
    } else if (waktu == 'hari_lain') {
      // Step 2: Show calendar popup
      if (!mounted) return;
      final tanggal = await showPopupPilihTanggal(context);
      if (tanggal == null || !mounted) return; // User cancelled

      await _issueBackdate(tanggal);
    }
  }

  /// Issue nomor for today
  Future<void> _issueHariIni() async {
    setState(() => _isLoading = true);

    try {
      final result = await _agendaService.issueTodayNumber(
        kategori: _selectedKategori!,
        kodeKlasifikasi: _kodeKlasifikasiController.text.trim(),
        tujuanSurat: _tujuanSuratController.text.trim(),
        perihal: _perihalController.text.trim(),
        pemohon: _pemohonController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Show success popup
      await showPopupHasilNomor(
        context,
        isSuccess: true,
        nomorLengkap: result.nomorLengkap,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return to home & trigger refresh
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final errorMsg = e.toString().replaceAll('Exception: ', '');

      // Show error popup
      await showPopupHasilNomor(
        context,
        isSuccess: false,
        errorMessage: errorMsg,
      );
    }
  }

  /// Issue backdate nomor
  Future<void> _issueBackdate(DateTime tanggal) async {
    setState(() => _isLoading = true);

    try {
      final result = await _agendaService.issueBackdateNumber(
        tanggal: tanggal,
        kategori: _selectedKategori!,
        kodeKlasifikasi: _kodeKlasifikasiController.text.trim(),
        tujuanSurat: _tujuanSuratController.text.trim(),
        perihal: _perihalController.text.trim(),
        pemohon: _pemohonController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Show success popup
      await showPopupHasilNomor(
        context,
        isSuccess: true,
        nomorLengkap: result.nomorLengkap,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return to home & trigger refresh
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final errorMsg = e.toString().replaceAll('Exception: ', '');

      // Show error popup (buffer habis, etc.)
      await showPopupHasilNomor(
        context,
        isSuccess: false,
        errorMessage: errorMsg,
      );
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceAlt,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                // ── Top bar ──
                _buildTopBar(),

                // ── Form content ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Kategori dropdown
                          _buildLabel('Pilih Kategori'),
                          const SizedBox(height: 6),
                          _buildKategoriDropdown(),
                          const SizedBox(height: 18),

                          // Kode Klasifikasi
                          _buildLabel('Masukkan Kode Klasifikasinya'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _kodeKlasifikasiController,
                            hint: 'Contoh: 500.12',
                            prefixIcon: Icons.tag_rounded,
                          ),
                          const SizedBox(height: 18),

                          // Perihal
                          _buildLabel('Masukkan Perihal'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _perihalController,
                            hint: 'Perihal Surat',
                            prefixIcon: Icons.subject_rounded,
                          ),
                          const SizedBox(height: 18),

                          // Tujuan Surat
                          _buildLabel('Masukkan Tujuan Surat'),
                          const SizedBox(height: 6),
                          _buildTextField(
                            controller: _tujuanSuratController,
                            hint: 'Tujuan Surat (Nama/Instansi/Pejabat)',
                            prefixIcon: Icons.send_rounded,
                          ),
                          const SizedBox(height: 18),

                          // Pemohon
                          Builder(
                            builder: (context) {
                              final auth = context.watch<AuthProvider>();
                              final user = auth.user;
                              final singkatan = user?.singkatanDisplay ?? 'Aptika';

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildLabel('Masukkan Pemohon Nomor'),
                                      if (singkatan.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            final current = _pemohonController.text.trim();
                                            if (current.isEmpty) {
                                              _pemohonController.text = '($singkatan)';
                                            } else if (!current.contains('($singkatan)')) {
                                              _pemohonController.text = '$current ($singkatan)';
                                            }
                                            setState(() {});
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              '+ ($singkatan)',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  _buildTextField(
                                    controller: _pemohonController,
                                    hint: 'Contoh: Adit ($singkatan)',
                                    prefixIcon: Icons.person_rounded,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 32),

                          // BUAT button section
                          Center(
                            child: Column(
                              children: [
                                const Text(
                                  'Buat Nomor Agenda',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _buildBuatButton(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Text(
            'Buat Nomor Agenda',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildKategoriDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedKategori,
          isExpanded: true,
          hint: const Text(
            'Pilih Kategori',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          dropdownColor: AppTheme.surface,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary, size: 24),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
          items: _kategoriOptions.map((k) {
            return DropdownMenuItem(
              value: k['value'],
              child: Text(k['label']!),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedKategori = val;
            });
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight, width: 1.2),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        onChanged: (_) => setState(() {}), // Trigger rebuild for validation
        decoration: InputDecoration(
          prefixIcon: Icon(prefixIcon, color: AppTheme.primary, size: 20),
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildBuatButton() {
    final isValid = _isFormValid;

    return SizedBox(
      width: 200,
      height: 48,
      child: ElevatedButton(
        onPressed: isValid ? _onBuatPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: isValid ? 3 : 0,
          shadowColor: AppTheme.primary.withValues(alpha: 0.3),
        ),
        child: const Text(
          'BUAT NOMOR',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: AppTheme.primary,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                'Memproses Nomor Agenda...',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
