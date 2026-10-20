import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../models/cat.dart';
import '../models/announcement.dart';
import '../models/reservation.dart';
import '../models/booking.dart';
import '../models/request_status.dart';
import '../utils/app_theme.dart';
import '../widgets/boutique_animations.dart';
import 'cat_detail_screen.dart';

import 'add_cat_screen.dart';
import 'owner/appointments_screen.dart';
import 'owner/discover_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _auth = FirebaseService();
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<List<Announcement>>? _announcementsSubscription;
  StreamSubscription<List<Reservation>>? _reservationsSubscription;
  StreamSubscription<List<Booking>>? _bookingsSubscription;
  bool _hasNewAnnouncements = false;
  DateTime _lastSeenNewsAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSeenAppointmentsAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<Reservation> _ownerReservations = [];
  List<Booking> _ownerBookings = [];
  int _appointmentsBadgeCount = 0;
  bool _hasUpdatedAppointmentResponse = false;

  @override
  void initState() {
    super.initState();
    _announcementsSubscription = _auth.getPublishedAnnouncements().listen((list) {
      if (mounted) {
        final hasNew = list.any((a) => a.createdAt.isAfter(_lastSeenNewsAt));
        if (hasNew != _hasNewAnnouncements) {
          setState(() => _hasNewAnnouncements = hasNew);
        }
      }
    });

    final uid = _auth.getCurrentUser()?.uid;
    if (uid != null) {
      _reservationsSubscription = _auth.getOwnerReservations(uid).listen((resList) {
        _ownerReservations = resList;
        _recomputeAppointmentsBadge();
      });
      _bookingsSubscription = _auth.getOwnerBookings(uid).listen((bookList) {
        _ownerBookings = bookList;
        _recomputeAppointmentsBadge();
      });
    }
  }

  void _recomputeAppointmentsBadge() {
    if (!mounted) return;
    final now = DateTime.now();

    int activeCount = 0;
    bool hasNewResponse = false;

    for (final r in _ownerReservations) {
      final eff = effectiveStatus(
        stored: r.status,
        start: r.requestedAt,
        end: r.requestedAt.add(const Duration(hours: 1)),
        now: now,
      );
      if (eff == RequestStatus.pending || eff == RequestStatus.accepted) {
        activeCount++;
      }
      if ((r.status == RequestStatus.accepted ||
              r.status == RequestStatus.declined ||
              r.status == RequestStatus.completed) &&
          r.updatedAt.isAfter(_lastSeenAppointmentsAt)) {
        hasNewResponse = true;
      }
    }

    for (final b in _ownerBookings) {
      final eff = effectiveStatus(
        stored: b.status,
        start: b.scheduledAt,
        end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
        now: now,
      );
      if (eff == RequestStatus.pending || eff == RequestStatus.accepted) {
        activeCount++;
      }
      if ((b.status == RequestStatus.accepted ||
              b.status == RequestStatus.declined ||
              b.status == RequestStatus.completed) &&
          b.updatedAt.isAfter(_lastSeenAppointmentsAt)) {
        hasNewResponse = true;
      }
    }

    if (activeCount != _appointmentsBadgeCount || hasNewResponse != _hasUpdatedAppointmentResponse) {
      setState(() {
        _appointmentsBadgeCount = activeCount;
        _hasUpdatedAppointmentResponse = hasNewResponse;
      });
    }
  }

  @override
  void dispose() {
    _announcementsSubscription?.cancel();
    _reservationsSubscription?.cancel();
    _bookingsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = _auth.getCurrentUser()?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    Widget bodyWidget;
    switch (_selectedIndex) {
      case 0:
        bodyWidget = _buildCatsList(userId);
        break;
      case 1:
        bodyWidget = const AppointmentsScreen();
        break;
      case 2:
        bodyWidget = DiscoverScreen(lastSeenAt: _lastSeenNewsAt);
        break;
      case 3:
      default:
        bodyWidget = _buildDashboard(userId);
        break;
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: (_selectedIndex == 1 || _selectedIndex == 2)
          ? null
          : AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.pets, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'PurrSync',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, letterSpacing: -0.3, color: Colors.white),
                  ),
                ],
              ),
              backgroundColor: AppTheme.ownerAccent,
              foregroundColor: Colors.white,
              actions: [
                const ThemeModeToggleButton(iconColor: Colors.white),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: TextButton.icon(
                    onPressed: () async {
                      await _auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.logout, color: Colors.white, size: 18),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
      body: bodyWidget,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            if (index == 1) {
              _hasUpdatedAppointmentResponse = false;
              _lastSeenAppointmentsAt = DateTime.now();
            }
            if (index == 2) {
              _hasNewAnnouncements = false;
              _lastSeenNewsAt = DateTime.now();
            }
            _selectedIndex = index;
          });
        },
        selectedItemColor: AppTheme.primaryTeal,
        unselectedItemColor: AppTheme.textSecondary,
        backgroundColor: AppTheme.surface,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.pets), label: 'My Cats'),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text(
                _appointmentsBadgeCount > 0 ? '$_appointmentsBadgeCount' : '!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
              ),
              backgroundColor: _hasUpdatedAppointmentResponse ? AppTheme.terracotta : AppTheme.primaryTeal,
              isLabelVisible: _appointmentsBadgeCount > 0 || _hasUpdatedAppointmentResponse,
              child: const Icon(Icons.calendar_month_outlined),
            ),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              label: const Text('!'),
              backgroundColor: AppTheme.terracotta,
              isLabelVisible: _hasNewAnnouncements,
              child: const Icon(Icons.explore_outlined),
            ),
            label: 'Discover',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddCatScreen()),
                );
              },
              backgroundColor: AppTheme.primaryTeal,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Cat', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildEmailVerificationBanner() {
    if (_auth.isEmailVerified()) return const SizedBox.shrink();
    final email = _auth.getCurrentUser()?.email ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: Color(0xFFE65100), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Email Not Verified',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE65100)),
                ),
                Text(
                  'Verify $email to enable full account notifications.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF795548)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _auth.sendEmailVerification();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Verification link sent to $email! Check your inbox.'),
                      backgroundColor: AppTheme.primaryTeal,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Resend', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
          ),
        ],
      ),
    );
  }

  Widget _buildCatsList(String userId) {
    return Column(
      children: [
        _buildEmailVerificationBanner(),
        // ============ SEARCH / FILTER ============
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search cats by name or breed...',
                hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 13.5),
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryTeal, size: 20),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Cat>>(
            stream: _auth.getCats(userId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load your cats.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const SkeletonCardList(itemCount: 4);
              }
              final allCats = snapshot.data!;
              final cats = _searchQuery.isEmpty
                  ? allCats
                  : allCats
                      .where((c) =>
                          c.name.toLowerCase().contains(_searchQuery) ||
                          c.breed.toLowerCase().contains(_searchQuery))
                      .toList();

              if (allCats.isEmpty) {
                return const BouncyPawEmptyState(
                  title: 'No cats registered yet',
                  subtitle: 'Tap "Add Cat" below to create your first feline health profile and track vaccines & weight.',
                  badgeIcon: Icons.favorite_rounded,
                );
              }
              if (cats.isEmpty) {
                return BouncyPawEmptyState(
                  title: 'No matching cats',
                  subtitle: 'No cats match "${_searchController.text}". Try a different name or breed.',
                  badgeIcon: Icons.search_off_rounded,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: cats.length,
                itemBuilder: (context, index) {
                  final cat = cats[index];
                  final hasImage = cat.imageBase64 != null && cat.imageBase64!.isNotEmpty;
                  return FadeInSlide(
                    key: ValueKey('cat_card_${cat.id}'),
                    delay: Duration(milliseconds: 35 * index),
                    duration: const Duration(milliseconds: 340),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardSurface(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.dividerFor(context)),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CatDetailScreen(cat: cat),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                // Larger Cat Photo wrapped in sweeping CatHealthRing + Hero transition
                                StreamBuilder<List<VaccineRecord>>(
                                  stream: _auth.getVaccines(cat.id),
                                  builder: (context, vaxSnap) {
                                    CatVaccineStatus ringStatus = CatVaccineStatus.safe;
                                    if (vaxSnap.hasData) {
                                      final vaxList = vaxSnap.data!;
                                      if (vaxList.any((v) => v.getStatus() == 'Overdue')) {
                                        ringStatus = CatVaccineStatus.overdue;
                                      } else if (vaxList.any((v) => v.getStatus() == 'Upcoming')) {
                                        ringStatus = CatVaccineStatus.dueSoon;
                                      }
                                    }
                                    return Hero(
                                      tag: 'cat_avatar_${cat.id}',
                                      child: CatHealthRing(
                                        status: ringStatus,
                                        size: 68,
                                        strokeWidth: 3.2,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryTealLight,
                                            shape: BoxShape.circle,
                                            image: hasImage
                                                ? DecorationImage(
                                                    image: MemoryImage(base64Decode(cat.imageBase64!)),
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                          ),
                                          child: !hasImage
                                              ? Center(
                                                  child: Text(
                                                    cat.name.isNotEmpty ? cat.name[0].toUpperCase() : '🐾',
                                                    style: const TextStyle(
                                                      fontSize: 24,
                                                      fontWeight: FontWeight.w800,
                                                      color: AppTheme.primaryTealDark,
                                                    ),
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            cat.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              letterSpacing: -0.2,
                                              color: AppTheme.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios, size: 13, color: AppTheme.textTertiary),
                                      ],
                                    ),
                                    if (cat.breed.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        cat.breed,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.surfaceMuted,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.borderLight),
                                          ),
                                          child: Text(
                                            cat.genderDisplay,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryTealLight,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.15)),
                                          ),
                                          child: Text(
                                            cat.ageDisplay,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primaryTealDark,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.terracottaLight,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.terracotta.withValues(alpha: 0.15)),
                                          ),
                                          child: Text(
                                            '${cat.weight} kg',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.terracotta,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard(String userId) {
    return StreamBuilder<List<Cat>>(
      stream: _auth.getCats(userId),
      builder: (context, catSnapshot) {
        if (!catSnapshot.hasData) {
          return const SkeletonCardList(itemCount: 3);
        }

        final cats = catSnapshot.data!;
        int totalCats = cats.length;

        return FutureBuilder<Map<String, int>>(
          future: _getAllVaccinesStats(cats),
          builder: (context, vaccineSnapshot) {
            int upcomingVaccines = 0;
            int overdueVaccines = 0;

            if (vaccineSnapshot.hasData) {
              final stats = vaccineSnapshot.data!;
              upcomingVaccines = stats['upcoming'] ?? 0;
              overdueVaccines = stats['overdue'] ?? 0;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Teal Gradient Header Card (#1E5E57 -> #2A6F68 -> #3C8F85)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.tealHeaderGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: const PawHeartbeatMotif(
                            size: 44,
                            color: Colors.white,
                            heartbeatColor: Color(0xFF81E6B8),
                            animate: true,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Health Dashboard',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Real-time overview of your feline wellness & alerts',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bento-box stats row
                  Row(
                    children: [
                      _buildBentoStatCard(
                        title: 'Total Cats',
                        value: totalCats.toString(),
                        icon: Icons.pets,
                        bgColor: AppTheme.statusSafeBg,
                        textColor: AppTheme.statusSafe,
                        iconColor: AppTheme.statusSafe,
                      ),
                      const SizedBox(width: 10),
                      _buildBentoStatCard(
                        title: 'Due Soon',
                        value: upcomingVaccines.toString(),
                        icon: Icons.notifications_active_outlined,
                        bgColor: AppTheme.statusWarningBg,
                        textColor: AppTheme.statusWarning,
                        iconColor: AppTheme.statusWarning,
                      ),
                      const SizedBox(width: 10),
                      _buildBentoStatCard(
                        title: 'Overdue',
                        value: overdueVaccines.toString(),
                        icon: Icons.warning_amber_rounded,
                        bgColor: AppTheme.statusDangerBg,
                        textColor: AppTheme.statusDanger,
                        iconColor: AppTheme.statusDanger,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Recent Activity & Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppTheme.textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (cats.isEmpty)
                    const BouncyPawEmptyState(
                      title: 'No health metrics yet',
                      subtitle: 'Add your first cat to start tracking vaccination status and weight trends.',
                      badgeIcon: Icons.monitor_heart_outlined,
                    )
                  else
                    ...cats.map((cat) => _buildCatSummary(cat)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, int>> _getAllVaccinesStats(List<Cat> cats) async {
    int upcoming = 0;
    int overdue = 0;

    for (var cat in cats) {
      try {
        final vaccines = await _auth.getVaccines(cat.id).first;
        for (var v in vaccines) {
          if (v.getStatus() == 'Upcoming') upcoming++;
          if (v.getStatus() == 'Overdue') overdue++;
        }
      } catch (_) {}
    }

    return {'upcoming': upcoming, 'overdue': overdue};
  }

  Widget _buildBentoStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required Color iconColor,
  }) {
    final numVal = num.tryParse(value) ?? 0;
    return Expanded(
      child: BouncingScale(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: textColor.withValues(alpha: 0.18)),
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(height: 6),
              AnimatedCounterText(
                value: numVal,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatSummary(Cat cat) {
    final hasImage = cat.imageBase64 != null && cat.imageBase64!.isNotEmpty;
    return StreamBuilder<List<VaccineRecord>>(
      stream: _auth.getVaccines(cat.id),
      builder: (context, snapshot) {
        String nextVaccine = 'No vaccines';
        Color badgeBg = AppTheme.surfaceMuted;
        Color badgeText = AppTheme.textSecondary;

        if (snapshot.hasData) {
          final vaccines = snapshot.data!;
          final now = DateTime.now();
          final upcomingVaccines = vaccines.where((v) => v.nextDueDate.isAfter(now)).toList();

          if (vaccines.any((v) => v.getStatus() == 'Overdue')) {
            nextVaccine = 'Vaccine overdue';
            badgeBg = AppTheme.statusDangerBg;
            badgeText = AppTheme.statusDanger;
          } else if (upcomingVaccines.isNotEmpty) {
            final nearest = upcomingVaccines.reduce((a, b) =>
                a.nextDueDate.isBefore(b.nextDueDate) ? a : b);
            final daysLeft = nearest.nextDueDate.difference(now).inDays;
            nextVaccine = '${nearest.type} in $daysLeft days';
            if (daysLeft <= 30) {
              badgeBg = AppTheme.statusWarningBg;
              badgeText = AppTheme.statusWarning;
            } else {
              badgeBg = AppTheme.statusSafeBg;
              badgeText = AppTheme.statusSafe;
            }
          } else if (vaccines.isNotEmpty) {
            nextVaccine = 'All vaccines up to date';
            badgeBg = AppTheme.statusSafeBg;
            badgeText = AppTheme.statusSafe;
          }
        }

        return FadeInSlide(
          duration: const Duration(milliseconds: 400),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => CatDetailScreen(cat: cat)),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryTealLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderLight),
                        image: hasImage
                            ? DecorationImage(
                                image: MemoryImage(base64Decode(cat.imageBase64!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: !hasImage
                          ? Center(
                              child: Text(
                                cat.name.isNotEmpty ? cat.name[0].toUpperCase() : '🐾',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cat.ageDisplay,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        nextVaccine,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
}