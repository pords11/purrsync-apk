import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/provider_profile.dart';
import '../models/request_status.dart';
import '../utils/app_theme.dart';
import '../utils/time_utils.dart';

/// A lightweight, boutique animation toolkit providing smooth micro-interactions,
/// staggered entrance fades, tactile bouncing presses, rolling metric counters,
/// custom paw-heartbeat brand motif, sweeping cat health rings, skeleton shimmers,
/// status steppers, and paw-print confetti celebrations.
///
/// Rules enforced to avoid jank:
/// - Durations kept between 200–450 ms with ease-out curves (`Curves.easeOutCubic`).
/// - Entrance animations play ONCE on initial mount (`initState`), never replaying
///   on subsequent Firestore stream rebuilds.
/// - Respects device accessibility (`MediaQuery.maybeDisableAnimationsOf(context)`).

typedef SlideDirection = AxisDirection;

/// Smooth entrance animation that fades in and slides into place.
/// Supports staggered delays for lists and grids (capped at the 8th item).
class FadeInSlide extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double slideOffset;
  final AxisDirection direction;
  final Curve curve;

  const FadeInSlide({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
    this.delay = Duration.zero,
    this.slideOffset = 20.0,
    this.direction = AxisDirection.up,
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<FadeInSlide> createState() => _FadeInSlideState();
}

class _FadeInSlideState extends State<FadeInSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    // Clamp duration to 200-450ms jank-free window
    final ms = widget.duration.inMilliseconds.clamp(200, 450);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: widget.curve);

    Offset beginOffset;
    switch (widget.direction) {
      case AxisDirection.up:
        beginOffset = Offset(0, widget.slideOffset / 100.0);
        break;
      case AxisDirection.down:
        beginOffset = Offset(0, -widget.slideOffset / 100.0);
        break;
      case AxisDirection.left:
        beginOffset = Offset(widget.slideOffset / 100.0, 0);
        break;
      case AxisDirection.right:
        beginOffset = Offset(-widget.slideOffset / 100.0, 0);
        break;
    }

    _slideAnimation = Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStarted) return;
    _hasStarted = true;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.value = 1.0;
      return;
    }

    // Cap staggered delay around the 8th item (max 280ms)
    final cappedDelayMs = math.min(widget.delay.inMilliseconds, 8 * 35);
    if (cappedDelayMs <= 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: cappedDelayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return widget.child;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

/// A tactile micro-interaction wrapper that subtly scales down when pressed
/// and springs back up on release, providing a boutique native feel.
class BouncingScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;

  const BouncingScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 160),
  });

  @override
  State<BouncingScale> createState() => _BouncingScaleState();
}

class _BouncingScaleState extends State<BouncingScale> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _isPressed = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _isPressed = false);
              widget.onTap?.call();
            },
      onTapCancel: widget.onTap == null ? null : () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: (_isPressed && !reduceMotion) ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Rolling counter animation for dashboard bento metrics (e.g. 0 -> 4).
class AnimatedCounterText extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final Duration duration;
  final String prefix;
  final String suffix;
  final int decimalPlaces;

  const AnimatedCounterText({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 420),
    this.prefix = '',
    this.suffix = '',
    this.decimalPlaces = 0,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      final formatted = decimalPlaces > 0
          ? value.toDouble().toStringAsFixed(decimalPlaces)
          : value.round().toString();
      return Text('$prefix$formatted$suffix', style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        final formatted = decimalPlaces > 0
            ? val.toStringAsFixed(decimalPlaces)
            : val.round().toString();
        return Text(
          '$prefix$formatted$suffix',
          style: style,
        );
      },
    );
  }
}

/// Subtle breathing pulse animation for urgent alert pills or live badges.
class PulseBadge extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final Duration duration;

  const PulseBadge({
    super.key,
    required this.child,
    this.minScale = 0.96,
    this.maxScale = 1.04,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  State<PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<PulseBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: widget.minScale, end: widget.maxScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return widget.child;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}

// =============================================================================
// 1. BRAND MOTIF: PAW + HEARTBEAT LINE (Splash, Empty States, Loading)
// =============================================================================

class PawHeartbeatMotif extends StatefulWidget {
  final double size;
  final Color? color;
  final Color? heartbeatColor;
  final bool animate;

  const PawHeartbeatMotif({
    super.key,
    this.size = 76,
    this.color,
    this.heartbeatColor,
    this.animate = true,
  });

  @override
  State<PawHeartbeatMotif> createState() => _PawHeartbeatMotifState();
}

class _PawHeartbeatMotifState extends State<PawHeartbeatMotif> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final primaryColor = widget.color ?? AppTheme.primary;
    final ecgColor = widget.heartbeatColor ?? AppTheme.statusSafe;

    if (reduceMotion || !widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _PawHeartbeatPainter(
            progress: 1.0,
            pawColor: primaryColor,
            ecgColor: ecgColor,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _PawHeartbeatPainter(
              progress: _controller.value.clamp(0.0, 1.0),
              pawColor: primaryColor,
              ecgColor: ecgColor,
            ),
          ),
        );
      },
    );
  }
}

class _PawHeartbeatPainter extends CustomPainter {
  final double progress;
  final Color pawColor;
  final Color ecgColor;

  _PawHeartbeatPainter({
    required this.progress,
    required this.pawColor,
    required this.ecgColor,
  });

  double _padScale(double start, double end) {
    if (progress <= start) return 0.0;
    if (progress >= end) return 1.0;
    final t = (progress - start) / (end - start);
    return Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final padPaint = Paint()
      ..color = pawColor
      ..style = PaintingStyle.fill;

    // 4 Toe pads pop in one by one
    final toes = [
      Offset(w * 0.25, h * 0.34),
      Offset(w * 0.41, h * 0.22),
      Offset(w * 0.59, h * 0.22),
      Offset(w * 0.75, h * 0.34),
    ];
    final toeAngles = [-0.28, -0.10, 0.10, 0.28];

    for (int i = 0; i < toes.length; i++) {
      final scale = _padScale(i * 0.10, (i * 0.10) + 0.32);
      if (scale <= 0) continue;
      canvas.save();
      canvas.translate(toes[i].dx, toes[i].dy);
      canvas.rotate(toeAngles[i]);
      canvas.scale(scale);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * 0.14, height: h * 0.19),
        padPaint,
      );
      canvas.restore();
    }

    // Main palm pad pops in
    final palmScale = _padScale(0.28, 0.65);
    if (palmScale > 0) {
      canvas.save();
      canvas.translate(w * 0.50, h * 0.60);
      canvas.scale(palmScale);
      final palmRect = RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset.zero, width: w * 0.48, height: h * 0.36),
        topLeft: Radius.circular(w * 0.22),
        topRight: Radius.circular(w * 0.22),
        bottomLeft: Radius.circular(w * 0.16),
        bottomRight: Radius.circular(w * 0.16),
      );
      canvas.drawRRect(palmRect, padPaint);
      canvas.restore();
    }

    // Heartbeat ECG line draws across the paw
    final ecgProgress = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
    if (ecgProgress > 0) {
      final fullPath = Path()
        ..moveTo(w * 0.12, h * 0.61)
        ..lineTo(w * 0.34, h * 0.61)
        ..lineTo(w * 0.41, h * 0.46)
        ..lineTo(w * 0.48, h * 0.74)
        ..lineTo(w * 0.55, h * 0.50)
        ..lineTo(w * 0.61, h * 0.61)
        ..lineTo(w * 0.88, h * 0.61);

      final metrics = fullPath.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final extracted = metric.extractPath(0, metric.length * ecgProgress);

        // White/surface halo for contrast over the paw pad
        final haloPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (w * 0.065).clamp(3.0, 6.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(extracted, haloPaint);

        final linePaint = Paint()
          ..color = ecgColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = (w * 0.042).clamp(2.0, 4.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(extracted, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PawHeartbeatPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pawColor != pawColor ||
        oldDelegate.ecgColor != ecgColor;
  }
}

/// Animated Splash Screen using the Paw + Heartbeat motif.
class AnimatedPawHeartbeatSplash extends StatelessWidget {
  final String message;

  const AnimatedPawHeartbeatSplash({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1F3834), const Color(0xFF152724)]
                      : [AppTheme.primarySubtle, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: AppTheme.softShadow,
              ),
              child: const PawHeartbeatMotif(size: 84, animate: true),
            ),
            const SizedBox(height: 24),
            Text(
              'PurrSync',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimaryColor(context),
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouncy Empty State with the Paw + Heartbeat brand motif.
class BouncyPawEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final IconData? badgeIcon;

  const BouncyPawEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.badgeIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return FadeInSlide(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F3834) : AppTheme.primarySubtle,
                      shape: BoxShape.circle,
                    ),
                    child: const PawHeartbeatMotif(size: 64, animate: true),
                  ),
                  if (badgeIcon != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface(context),
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Icon(badgeIcon, size: 18, color: AppTheme.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimaryColor(context),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppTheme.textSecondaryColor(context),
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 22),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 2. CAT HEALTH RING: Sweeping Circular/Squircle Ring Colored by Vaccine Status
// =============================================================================

enum CatVaccineStatus {
  safe,
  dueSoon,
  overdue;

  Color get color {
    switch (this) {
      case CatVaccineStatus.safe:
        return AppTheme.statusSafe;
      case CatVaccineStatus.dueSoon:
        return AppTheme.statusWarning;
      case CatVaccineStatus.overdue:
        return AppTheme.statusDanger;
    }
  }

  String get label {
    switch (this) {
      case CatVaccineStatus.safe:
        return 'Up to Date';
      case CatVaccineStatus.dueSoon:
        return 'Due Soon';
      case CatVaccineStatus.overdue:
        return 'Overdue';
    }
  }
}

class CatHealthRing extends StatelessWidget {
  final Widget child;
  final CatVaccineStatus status;
  final double size;
  final double strokeWidth;
  final bool isCircular;

  const CatHealthRing({
    super.key,
    required this.child,
    required this.status,
    this.size = 68,
    this.strokeWidth = 3.2,
    this.isCircular = true,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final ringColor = status.color;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return CustomPaint(
          foregroundPainter: _HealthRingPainter(
            progress: progress,
            color: ringColor,
            strokeWidth: strokeWidth,
          ),
          child: Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(strokeWidth + 3.0),
            child: ClipOval(child: child),
          ),
        );
      },
    );
  }
}

class _HealthRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _HealthRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    // Subtle track ring
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Sweeping status ring
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

// =============================================================================
// 3. SKELETON SHIMMER (Replaces Spinners While Lists Are Loading)
// =============================================================================

class SkeletonCardList extends StatefulWidget {
  final int itemCount;
  final double cardHeight;
  final EdgeInsetsGeometry padding;

  const SkeletonCardList({
    super.key,
    this.itemCount = 3,
    this.cardHeight = 96,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  State<SkeletonCardList> createState() => _SkeletonCardListState();
}

class _SkeletonCardListState extends State<SkeletonCardList> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final baseColor = isDark ? const Color(0xFF1E2D2B) : const Color(0xFFE5ECE9);
    final highlightColor = isDark ? const Color(0xFF2B3F3C) : const Color(0xFFF3F7F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shimmerColor = Color.lerp(baseColor, highlightColor, _controller.value)!;
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.padding,
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return Container(
              height: widget.cardHeight,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.dividerFor(context)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 14,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 96,
                          height: 11,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// 4. "OPEN NOW" PULSING DOT (Computed from Clock-Picked Hours)
// =============================================================================

class OpenStatusPill extends StatelessWidget {
  final ProviderProfile provider;
  final bool compact;

  const OpenStatusPill({
    super.key,
    required this.provider,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = TimeUtils.isWithinHours(DateTime.now(), provider);
    final dotColor = isOpen ? AppTheme.statusSafe : AppTheme.textSecondaryColor(context);
    final bgColor = isOpen
        ? AppTheme.statusSafe.withValues(alpha: 0.14)
        : AppTheme.dividerFor(context).withValues(alpha: 0.5);
    final textColor = isOpen ? AppTheme.statusSafe : AppTheme.textSecondaryColor(context);

    final dot = Container(
      width: compact ? 7 : 8,
      height: compact ? 7 : 8,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        boxShadow: isOpen
            ? [
                BoxShadow(
                  color: AppTheme.statusSafe.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOpen
              ? AppTheme.statusSafe.withValues(alpha: 0.3)
              : AppTheme.dividerFor(context),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isOpen ? PulseBadge(minScale: 0.85, maxScale: 1.2, child: dot) : dot,
          const SizedBox(width: 6),
          Text(
            isOpen ? 'Open Now' : 'Closed',
            style: TextStyle(
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 5. STATUS STEPPER: Pending -> Accepted -> Completed with Smooth Fill
// =============================================================================

class AppointmentStatusStepper extends StatelessWidget {
  final RequestStatus status;

  const AppointmentStatusStepper({
    super.key,
    required this.status,
  });

  int get _activeStep {
    switch (status) {
      case RequestStatus.pending:
        return 1;
      case RequestStatus.accepted:
        return 2;
      case RequestStatus.completed:
        return 3;
      case RequestStatus.declined:
      case RequestStatus.cancelled:
      case RequestStatus.expired:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _activeStep;
    if (step == 0) {
      // Closed negatively (Declined / Cancelled / Expired)
      return const SizedBox.shrink();
    }

    final activeColor = status == RequestStatus.pending
        ? AppTheme.statusWarning
        : AppTheme.statusSafe;
    final inactiveColor = AppTheme.dividerFor(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              _buildStepNode(
                label: 'Pending',
                reached: step >= 1,
                current: step == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
              Expanded(
                child: _buildAnimatedConnector(
                  filled: step >= 2,
                  activeColor: AppTheme.statusSafe,
                  inactiveColor: inactiveColor,
                ),
              ),
              _buildStepNode(
                label: 'Accepted',
                reached: step >= 2,
                current: step == 2,
                activeColor: AppTheme.statusSafe,
                inactiveColor: inactiveColor,
              ),
              Expanded(
                child: _buildAnimatedConnector(
                  filled: step >= 3,
                  activeColor: AppTheme.statusSafe,
                  inactiveColor: inactiveColor,
                ),
              ),
              _buildStepNode(
                label: 'Completed',
                reached: step >= 3,
                current: step == 3,
                activeColor: AppTheme.statusSafe,
                inactiveColor: inactiveColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepNode({
    required String label,
    required bool reached,
    required bool current,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final color = reached ? activeColor : inactiveColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: current ? 18 : 14,
          height: current ? 18 : 14,
          decoration: BoxDecoration(
            color: reached ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: reached
              ? const Icon(Icons.check, size: 10, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: current ? FontWeight.w800 : FontWeight.w600,
            color: reached ? color : AppTheme.textHint,
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedConnector({
    required bool filled,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 3.5,
          child: Stack(
            children: [
              Container(color: inactiveColor),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                widthFactor: filled ? 1.0 : 0.0,
                alignment: Alignment.centerLeft,
                child: Container(color: activeColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 6. SUCCESS MOMENT: Animated Self-Drawing Checkmark + Paw-Print Confetti
// =============================================================================

Future<void> showPurrSyncSuccessOverlay(
  BuildContext context, {
  required String title,
  String? subtitle,
}) async {
  if (!context.mounted) return;
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (reduceMotion) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(title), backgroundColor: AppTheme.statusSafe),
    );
    return;
  }

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Success',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogCtx, anim1, anim2) {
      Future.delayed(const Duration(milliseconds: 950), () {
        if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
          Navigator.of(dialogCtx).pop();
        }
      });
      return Center(
        child: Material(
          color: Colors.transparent,
          child: _SuccessCelebrationCard(title: title, subtitle: subtitle),
        ),
      );
    },
  );
}

class _SuccessCelebrationCard extends StatefulWidget {
  final String title;
  final String? subtitle;

  const _SuccessCelebrationCard({required this.title, this.subtitle});

  @override
  State<_SuccessCelebrationCard> createState() => _SuccessCelebrationCardState();
}

class _SuccessCelebrationCardState extends State<_SuccessCelebrationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      builder: (context, _) {
        final t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Small paw-print confetti burst around the card
            ...List.generate(6, (i) {
              final angle = (i * math.pi / 3) - math.pi / 6;
              final distance = 75.0 + (60.0 * t);
              final dx = math.cos(angle) * distance;
              final dy = math.sin(angle) * distance;
              final opacity = (1.0 - (t * 0.85)).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(dx, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Icon(
                    Icons.pets_rounded,
                    size: 18,
                    color: i.isEven ? AppTheme.statusSafe : AppTheme.statusWarning,
                  ),
                ),
              );
            }),
            Container(
              width: 270,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface(context),
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: CustomPaint(
                      painter: _SelfDrawingCheckPainter(
                        progress: t,
                        color: AppTheme.statusSafe,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimaryColor(context),
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SelfDrawingCheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  _SelfDrawingCheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Soft circle fill
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * progress.clamp(0.0, 1.0), bgPaint);

    // Circle ring
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * (progress * 1.3).clamp(0.0, 1.0),
      false,
      ringPaint,
    );

    // Self-drawing checkmark
    final checkProgress = ((progress - 0.25) / 0.75).clamp(0.0, 1.0);
    if (checkProgress > 0) {
      final path = Path()
        ..moveTo(size.width * 0.28, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.67)
        ..lineTo(size.width * 0.73, size.height * 0.36);

      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final extract = metrics.first.extractPath(0, metrics.first.length * checkProgress);
        final checkPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(extract, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SelfDrawingCheckPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
