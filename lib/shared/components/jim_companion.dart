import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';
import '../models/app_models.dart';

class JimCompanionAvatar extends StatelessWidget {
  const JimCompanionAvatar({
    super.key,
    required this.stage,
    this.size = 160,
    this.showLabel = false,
  });

  final JimCompanionStage stage;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _JimCompanionPainter(stage: stage),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 10),
          Text(
            _stageLabel(stage),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: JimColors.inkSoft,
                  letterSpacing: .5,
                ),
          ),
        ],
      ],
    );
  }

  static String _stageLabel(JimCompanionStage stage) {
    return switch (stage) {
      JimCompanionStage.softBase => 'Soft base',
      JimCompanionStage.activeBase => 'Active base',
      JimCompanionStage.armored1 => 'Armored I',
      JimCompanionStage.armored2 => 'Armored II',
      JimCompanionStage.jackedArmorFinal => 'Jacked final',
    };
  }
}

class _JimCompanionPainter extends CustomPainter {
  const _JimCompanionPainter({
    required this.stage,
  });

  final JimCompanionStage stage;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final bodyColor = switch (stage) {
      JimCompanionStage.softBase => const Color(0xFFF8FAFF),
      JimCompanionStage.activeBase => const Color(0xFFF4F9FF),
      JimCompanionStage.armored1 => const Color(0xFFF1F7FF),
      JimCompanionStage.armored2 => const Color(0xFFEEF5FF),
      JimCompanionStage.jackedArmorFinal => const Color(0xFFEBF3FF),
    };
    final accentColor = switch (stage) {
      JimCompanionStage.softBase => JimColors.accent,
      JimCompanionStage.activeBase => JimColors.accentStrong,
      JimCompanionStage.armored1 => JimColors.armor,
      JimCompanionStage.armored2 => JimColors.armorStrong,
      JimCompanionStage.jackedArmorFinal => JimColors.energy,
    };

    final shadowPaint = Paint()..color = JimColors.shadowStrong;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, size.height - 16),
        width: size.width * .52,
        height: size.height * .08,
      ),
      shadowPaint,
    );

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, bodyColor, bodyColor.withValues(alpha: .92)],
      ).createShader(Offset.zero & size);
    final outline = Paint()
      ..color = JimColors.insetLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final body = RRect.fromLTRBR(
      center.dx - size.width * .23,
      center.dy - size.height * .12,
      center.dx + size.width * .23,
      center.dy + size.height * .23,
      Radius.circular(size.width * .18),
    );
    final leftArm = RRect.fromLTRBR(
      center.dx - size.width * .35,
      center.dy - size.height * .04,
      center.dx - size.width * .17,
      center.dy + size.height * .22,
      Radius.circular(size.width * .12),
    );
    final rightArm = RRect.fromLTRBR(
      center.dx + size.width * .17,
      center.dy - size.height * .04,
      center.dx + size.width * .35,
      center.dy + size.height * .22,
      Radius.circular(size.width * .12),
    );
    final head = Rect.fromCenter(
      center: Offset(center.dx, center.dy - size.height * .22),
      width: size.width * .38,
      height: size.height * .26,
    );

    canvas.drawRRect(leftArm, bodyPaint);
    canvas.drawRRect(rightArm, bodyPaint);
    canvas.drawRRect(body, bodyPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, Radius.circular(size.width * .16)),
      bodyPaint,
    );

    canvas.drawRRect(leftArm, outline);
    canvas.drawRRect(rightArm, outline);
    canvas.drawRRect(body, outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, Radius.circular(size.width * .16)),
      outline,
    );

    final eyePaint = Paint()
      ..color = JimColors.ink
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    final eyeY = center.dy - size.height * .21;
    final leftEye = Offset(center.dx - size.width * .08, eyeY);
    final rightEye = Offset(center.dx + size.width * .08, eyeY);
    canvas.drawCircle(leftEye, 2.5, eyePaint);
    canvas.drawCircle(rightEye, 2.5, eyePaint);
    canvas.drawLine(leftEye, rightEye, eyePaint);

    final blush = Paint()..color = accentColor.withValues(alpha: .14);
    canvas.drawCircle(
      Offset(center.dx - size.width * .12, center.dy - size.height * .15),
      8,
      blush,
    );
    canvas.drawCircle(
      Offset(center.dx + size.width * .12, center.dy - size.height * .15),
      8,
      blush,
    );

    _paintFluff(canvas, size, center, accentColor);
    _paintArmor(canvas, size, center, accentColor);
  }

  void _paintFluff(
    Canvas canvas,
    Size size,
    Offset center,
    Color accentColor,
  ) {
    final fluffPaint = Paint()
      ..color = accentColor.withValues(alpha: .10)
      ..style = PaintingStyle.fill;
    final points = [
      Offset(center.dx - size.width * .18, center.dy - size.height * .28),
      Offset(center.dx, center.dy - size.height * .34),
      Offset(center.dx + size.width * .18, center.dy - size.height * .28),
    ];
    for (final point in points) {
      canvas.drawCircle(point, size.width * .045, fluffPaint);
    }
  }

  void _paintArmor(
    Canvas canvas,
    Size size,
    Offset center,
    Color accentColor,
  ) {
    if (stage == JimCompanionStage.softBase) {
      return;
    }

    final armorPaint = Paint()
      ..color = accentColor.withValues(alpha: .92)
      ..style = PaintingStyle.fill;
    final trimPaint = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final chest = RRect.fromLTRBR(
      center.dx - size.width * .12,
      center.dy,
      center.dx + size.width * .12,
      center.dy + size.height * .12,
      Radius.circular(size.width * .06),
    );
    canvas.drawRRect(chest, armorPaint);
    canvas.drawRRect(chest, trimPaint);

    if (stage.index >= JimCompanionStage.armored1.index) {
      final shoulderLeft = RRect.fromLTRBR(
        center.dx - size.width * .28,
        center.dy - size.height * .03,
        center.dx - size.width * .14,
        center.dy + size.height * .07,
        Radius.circular(size.width * .05),
      );
      final shoulderRight = RRect.fromLTRBR(
        center.dx + size.width * .14,
        center.dy - size.height * .03,
        center.dx + size.width * .28,
        center.dy + size.height * .07,
        Radius.circular(size.width * .05),
      );
      canvas.drawRRect(shoulderLeft, armorPaint);
      canvas.drawRRect(shoulderRight, armorPaint);
      canvas.drawRRect(shoulderLeft, trimPaint);
      canvas.drawRRect(shoulderRight, trimPaint);
    }

    if (stage.index >= JimCompanionStage.armored2.index) {
      final belt = RRect.fromLTRBR(
        center.dx - size.width * .14,
        center.dy + size.height * .13,
        center.dx + size.width * .14,
        center.dy + size.height * .18,
        Radius.circular(size.width * .03),
      );
      canvas.drawRRect(belt, armorPaint);
      canvas.drawRRect(belt, trimPaint);
    }

    if (stage == JimCompanionStage.jackedArmorFinal) {
      final energyPaint = Paint()
        ..color = JimColors.energy.withValues(alpha: .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawArc(
        Rect.fromCenter(
          center: center,
          width: size.width * .78,
          height: size.height * .82,
        ),
        3.7,
        1.1,
        false,
        energyPaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: center,
          width: size.width * .88,
          height: size.height * .92,
        ),
        -.55,
        1.1,
        false,
        energyPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _JimCompanionPainter oldDelegate) {
    return oldDelegate.stage != stage;
  }
}
