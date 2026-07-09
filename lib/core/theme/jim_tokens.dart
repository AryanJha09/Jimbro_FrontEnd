import 'package:flutter/material.dart';

class JimColors {
  static const shell = Color(0xFFFCF9F4);
  static const eggshell = Color(0xFFF7F1E9);
  static const galleryWhite = Color(0xFFF4F0E9);
  static const ivory = Color(0xFFEEE8DF);
  static const mistStone = Color(0xFFE7E0D8);
  static const paleStone = Color(0xFFD7DFF0);
  static const limestone = Color(0xFFC2CCE6);
  static const accent = Color(0xFF5E78D6);
  static const accentStrong = Color(0xFF3558C8);
  static const accentSoft = Color(0xFFE7EEFF);
  static const accentLine = Color(0xFFBCCAF5);
  static const armor = Color(0xFF8EA6E9);
  static const armorStrong = Color(0xFF5D77D9);
  static const energy = Color(0xFFF0AE55);
  static const ink = Color(0xFF313542);
  static const inkSoft = Color(0xFF5B6071);
  static const inkMuted = Color(0xFF8D92A3);
  static const plaque = Color(0xFFFFFDF9);
  static const line = Color(0x217C8498);
  static const insetLine = Color(0x2BABB3C8);
  static const success = Color(0xFF5E8B71);
  static const warning = Color(0xFFAE8256);
  static const terracotta = Color(0xFFA36460);
  static const shadow = Color(0x120E1D35);
  static const shadowStrong = Color(0x150E1D35);
  static const highlight = Color(0xCCFFFFFF);
}

class JimSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double ml = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double xxxl = 56;
}

class JimRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double hero = 38;
  static const double control = 18;
  static const double card = 22;
  static const double sheet = 30;
  static const double oldSm = 14;
  static const double oldMd = 20;
  static const double oldLg = 30;
  static const double pill = 999;
}

class JimLegacyRadius {
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 30;
}

class JimElevation {
  static List<BoxShadow> card = const [
    BoxShadow(
      color: JimColors.shadow,
      blurRadius: 32,
      offset: Offset(10, 12),
    ),
    BoxShadow(
      color: JimColors.highlight,
      blurRadius: 24,
      offset: Offset(-8, -8),
    ),
  ];
  static List<BoxShadow> soft = const [
    BoxShadow(
      color: JimColors.shadow,
      blurRadius: 24,
      offset: Offset(0, 9),
    ),
    BoxShadow(
      color: Color(0x66FFFFFF),
      blurRadius: 0,
      offset: Offset(0, -1),
    ),
  ];
  static List<BoxShadow> lifted = const [
    BoxShadow(
      color: JimColors.shadowStrong,
      blurRadius: 30,
      offset: Offset(0, 16),
    ),
  ];
}

class JimMotion {
  static const loaderSpin = Duration(milliseconds: 2200);
  static const loaderSettle = Duration(milliseconds: 950);
  static const screenFade = Duration(milliseconds: 720);
  static const gentle = Duration(milliseconds: 260);
}

class JimTextures extends StatelessWidget {
  const JimTextures({
    super.key,
    this.opacity = .08,
  });

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        painter: _DustPainter(),
      ),
    );
  }
}

class JimLightTexture extends StatelessWidget {
  const JimLightTexture({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: const [
          JimTextures(opacity: .07),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.25,
                colors: [
                  Color(0x33FFFFFF),
                  Color(0x00FFFFFF),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DustPainter extends CustomPainter {
  const _DustPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = JimColors.ink.withValues(alpha: .03);
    final marble = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x16FFFFFF),
          Color(0x00FFFFFF),
          Color(0x0D7A8BBD),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, marble);

    for (int i = 0; i < 18; i++) {
      final dx = (size.width / 17) * i;
      final path = Path()
        ..moveTo(dx, 0)
        ..quadraticBezierTo(
          dx + 18,
          size.height * .3,
          dx - 6,
          size.height,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = JimColors.ink.withValues(alpha: .015)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    for (int row = 0; row < 16; row++) {
      final y = (size.height / 15) * row;
      for (int col = 0; col < 10; col++) {
        final x = (size.width / 9) * col + ((row % 2) * 10);
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
