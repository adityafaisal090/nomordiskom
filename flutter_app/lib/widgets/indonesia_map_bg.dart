import 'package:flutter/material.dart';

/// Reusable Indonesia map silhouette watermark widget.
/// Displays a semi-transparent grey silhouette of Indonesia as background decoration.
/// Used on Login and Home screens per design.md §9.1.
class IndonesiaMapBackground extends StatelessWidget {
  final double opacity;
  final Alignment alignment;

  const IndonesiaMapBackground({
    super.key,
    this.opacity = 0.15,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: opacity,
          child: CustomPaint(
            size: Size(MediaQuery.of(context).size.width * 0.95, 200),
            painter: _IndonesiaMapPainter(),
          ),
        ),
      ),
    );
  }
}

class _IndonesiaMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.fill;

    // Simplified Indonesia archipelago silhouette
    // Sumatra
    final sumatra = Path();
    sumatra.moveTo(size.width * 0.05, size.height * 0.35);
    sumatra.lineTo(size.width * 0.08, size.height * 0.25);
    sumatra.lineTo(size.width * 0.14, size.height * 0.18);
    sumatra.lineTo(size.width * 0.18, size.height * 0.22);
    sumatra.lineTo(size.width * 0.22, size.height * 0.30);
    sumatra.lineTo(size.width * 0.20, size.height * 0.48);
    sumatra.lineTo(size.width * 0.15, size.height * 0.58);
    sumatra.lineTo(size.width * 0.10, size.height * 0.55);
    sumatra.lineTo(size.width * 0.07, size.height * 0.45);
    sumatra.close();
    canvas.drawPath(sumatra, paint);

    // Java
    final java = Path();
    java.moveTo(size.width * 0.22, size.height * 0.62);
    java.lineTo(size.width * 0.28, size.height * 0.58);
    java.lineTo(size.width * 0.36, size.height * 0.58);
    java.lineTo(size.width * 0.42, size.height * 0.62);
    java.lineTo(size.width * 0.38, size.height * 0.68);
    java.lineTo(size.width * 0.30, size.height * 0.68);
    java.lineTo(size.width * 0.24, size.height * 0.66);
    java.close();
    canvas.drawPath(java, paint);

    // Kalimantan
    final kalimantan = Path();
    kalimantan.moveTo(size.width * 0.30, size.height * 0.20);
    kalimantan.lineTo(size.width * 0.35, size.height * 0.12);
    kalimantan.lineTo(size.width * 0.42, size.height * 0.10);
    kalimantan.lineTo(size.width * 0.48, size.height * 0.15);
    kalimantan.lineTo(size.width * 0.46, size.height * 0.28);
    kalimantan.lineTo(size.width * 0.42, size.height * 0.42);
    kalimantan.lineTo(size.width * 0.36, size.height * 0.45);
    kalimantan.lineTo(size.width * 0.30, size.height * 0.38);
    kalimantan.lineTo(size.width * 0.28, size.height * 0.28);
    kalimantan.close();
    canvas.drawPath(kalimantan, paint);

    // Sulawesi
    final sulawesi = Path();
    sulawesi.moveTo(size.width * 0.52, size.height * 0.18);
    sulawesi.lineTo(size.width * 0.55, size.height * 0.12);
    sulawesi.lineTo(size.width * 0.58, size.height * 0.15);
    sulawesi.lineTo(size.width * 0.60, size.height * 0.25);
    sulawesi.lineTo(size.width * 0.57, size.height * 0.32);
    sulawesi.lineTo(size.width * 0.60, size.height * 0.38);
    sulawesi.lineTo(size.width * 0.56, size.height * 0.45);
    sulawesi.lineTo(size.width * 0.52, size.height * 0.40);
    sulawesi.lineTo(size.width * 0.50, size.height * 0.30);
    sulawesi.close();
    canvas.drawPath(sulawesi, paint);

    // Small islands (Bali, Nusa Tenggara chain)
    _drawIsland(canvas, paint, size, 0.44, 0.62, 0.03);
    _drawIsland(canvas, paint, size, 0.49, 0.64, 0.025);
    _drawIsland(canvas, paint, size, 0.54, 0.63, 0.03);
    _drawIsland(canvas, paint, size, 0.59, 0.62, 0.025);
    _drawIsland(canvas, paint, size, 0.63, 0.60, 0.02);

    // Maluku islands
    _drawIsland(canvas, paint, size, 0.68, 0.35, 0.025);
    _drawIsland(canvas, paint, size, 0.72, 0.40, 0.02);
    _drawIsland(canvas, paint, size, 0.70, 0.48, 0.02);

    // Papua
    final papua = Path();
    papua.moveTo(size.width * 0.78, size.height * 0.20);
    papua.lineTo(size.width * 0.82, size.height * 0.12);
    papua.lineTo(size.width * 0.90, size.height * 0.10);
    papua.lineTo(size.width * 0.95, size.height * 0.18);
    papua.lineTo(size.width * 0.93, size.height * 0.30);
    papua.lineTo(size.width * 0.88, size.height * 0.45);
    papua.lineTo(size.width * 0.82, size.height * 0.48);
    papua.lineTo(size.width * 0.78, size.height * 0.38);
    papua.lineTo(size.width * 0.76, size.height * 0.28);
    papua.close();
    canvas.drawPath(papua, paint);
  }

  void _drawIsland(Canvas canvas, Paint paint, Size size,
      double cx, double cy, double radius) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * cx, size.height * cy),
        width: size.width * radius * 2,
        height: size.height * radius * 1.2,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
