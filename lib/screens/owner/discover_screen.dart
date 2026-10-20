import 'package:flutter/material.dart';
import '../../models/provider_profile.dart';
import '../../models/announcement.dart';
import '../../models/user_role.dart';
import '../../services/firebase_service.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/boutique_animations.dart';
import 'provider_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  final DateTime? lastSeenAt;
  const DiscoverScreen({super.key, this.lastSeenAt});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _db = FirebaseService();
  final ApiService _api = ApiService();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _catFact;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCatFact();
  }

  Future<void> _loadCatFact() async {
    final fact = await _api.fetchDailyCatFact();
    if (mounted) {
      setState(() {
        _catFact = fact;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Discover & Community', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        actions: [
          const ThemeModeToggleButton(iconColor: Colors.white),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: () async {
                await _db.signOut();
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
          tabs: const [
            Tab(icon: Icon(Icons.local_hospital_outlined), text: 'Vet Clinics'),
            Tab(icon: Icon(Icons.campaign_outlined), text: 'Community & News'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUnifiedProvidersList(),
          _buildNewsFeed(),
        ],
      ),
    );
  }

  // ============ UNIFIED PROVIDERS LIST (VET / CLINIC) ============
  Widget _buildUnifiedProvidersList() {
    return Column(
      children: [
        // Daily Cat Care Tip from REST API
        if (_catFact != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryTealLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppTheme.primaryTeal, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daily Cat Care Fact (Live REST API)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _catFact!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by clinic, vet, specialty, or city...',
                hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 13.5),
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryTeal, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ProviderProfile>>(
            stream: _db.getAllProviders(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error loading directory: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)));
              }
              if (!snapshot.hasData) {
                return const SkeletonCardList(itemCount: 3);
              }

              final all = snapshot.data!;
              final active = all.where((p) => p.active).toList();
              final filtered = _searchQuery.isEmpty
                  ? active
                  : active.where((p) {
                      return p.displayName.toLowerCase().contains(_searchQuery) ||
                          p.city.toLowerCase().contains(_searchQuery) ||
                          (p.specialty != null && p.specialty!.toLowerCase().contains(_searchQuery));
                    }).toList();

              if (active.isEmpty) {
                return const BouncyPawEmptyState(
                  title: 'No vet clinics listed yet',
                  subtitle: 'Registered clinics and veterinarians will appear here with live operating hours.',
                  badgeIcon: Icons.local_hospital_outlined,
                );
              }

              if (filtered.isEmpty) {
                return BouncyPawEmptyState(
                  title: 'No matching clinics',
                  subtitle: 'No results matching "$_searchQuery".',
                  badgeIcon: Icons.search_off_rounded,
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  final isVet = p.role == UserRole.vet;
                  final accentColor = isVet ? AppTheme.vetAccent : AppTheme.clinicAccent;
                  final accentBg = isVet ? const Color(0xFFE8EEF2) : const Color(0xFFEAF2EB);

                  return FadeInSlide(
                    key: ValueKey('provider_${p.id}'),
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
                                builder: (context) => ProviderDetailScreen(provider: p),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Hero(
                                  tag: 'provider_avatar_${p.id}',
                                  child: Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: accentBg,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                                    ),
                                    child: Icon(
                                      isVet ? Icons.medical_services_outlined : Icons.local_hospital_outlined,
                                      color: accentColor,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.displayName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              letterSpacing: -0.2,
                                              color: AppTheme.textPrimaryColor(context),
                                            ),
                                          ),
                                        ),
                                        OpenStatusPill(provider: p, compact: true),
                                      ],
                                    ),
                                    if (isVet && p.specialty != null && p.specialty!.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.terracottaLight,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          p.specialty!,
                                          style: const TextStyle(
                                            color: AppTheme.terracotta,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 13, color: AppTheme.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          p.city.isNotEmpty ? p.city : 'Location not set',
                                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceMuted,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.schedule, size: 12, color: AppTheme.primaryTeal),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              p.hoursLabel,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: AppTheme.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
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

  // ============ NEWS / ANNOUNCEMENTS FEED ============
  Widget _buildNewsFeed() {
    return StreamBuilder<List<Announcement>>(
      stream: _db.getPublishedAnnouncements(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load announcements: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)));
        }
        if (!snapshot.hasData) {
          return const SkeletonCardList(itemCount: 3);
        }

        final list = snapshot.data!;
        final now = DateTime.now();
        final lastSeen = widget.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        final visible = list.where((item) {
          if (item.expiresAt != null && item.expiresAt!.isBefore(now)) {
            return false;
          }
          if (item.type == 'event' && item.eventDate != null) {
            final dayAfter = DateTime(item.eventDate!.year, item.eventDate!.month, item.eventDate!.day).add(const Duration(days: 1));
            if (dayAfter.isBefore(now)) return false;
          }
          return true;
        }).toList();

        if (visible.isEmpty) {
          return const BouncyPawEmptyState(
            title: 'No community news yet',
            subtitle: 'Check back later for veterinary health alerts, vaccination drives, and clinic announcements.',
            badgeIcon: Icons.campaign_outlined,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final item = visible[index];
            final isEvent = item.type == 'event';
            final isNew = item.createdAt.isAfter(lastSeen);

            return FadeInSlide(
              delay: Duration(milliseconds: 35 * index),
              child: BouncingScale(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.borderLight),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Builder(
                              builder: (context) {
                                Color badgeBg;
                                Color badgeFg;
                                IconData badgeIcon;
                                String badgeLabel;

                                switch (item.type) {
                                  case 'drive':
                                  case 'event':
                                    badgeBg = const Color(0xFFE8F5E9);
                                    badgeFg = const Color(0xFF2E7D32);
                                    badgeIcon = Icons.medical_services;
                                    badgeLabel = 'VACCINE & HEALTH DRIVE';
                                    break;
                                  case 'schedule':
                                    badgeBg = const Color(0xFFFFF3E0);
                                    badgeFg = const Color(0xFFE65100);
                                    badgeIcon = Icons.access_time_filled;
                                    badgeLabel = 'HOURS / SCHEDULE';
                                    break;
                                  case 'service_update':
                                    badgeBg = const Color(0xFFE3F2FD);
                                    badgeFg = const Color(0xFF1565C0);
                                    badgeIcon = Icons.stars;
                                    badgeLabel = 'SERVICE UPDATE';
                                    break;
                                  case 'payment_facility':
                                    badgeBg = const Color(0xFFF3E5F5);
                                    badgeFg = const Color(0xFF7B1FA2);
                                    badgeIcon = Icons.account_balance_wallet;
                                    badgeLabel = 'PAYMENT & FACILITY';
                                    break;
                                  case 'others':
                                    badgeBg = const Color(0xFFECEFF1);
                                    badgeFg = const Color(0xFF455A64);
                                    badgeIcon = Icons.campaign;
                                    badgeLabel = 'SPECIAL NOTICE';
                                    break;
                                  case 'general':
                                  default:
                                    badgeBg = AppTheme.primaryTealLight;
                                    badgeFg = AppTheme.primaryTealDark;
                                    badgeIcon = Icons.health_and_safety;
                                    badgeLabel = 'HEALTH UPDATE';
                                    break;
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: badgeBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(badgeIcon, size: 13, color: badgeFg),
                                      const SizedBox(width: 4),
                                      Text(
                                        badgeLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: badgeFg,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            if (isNew) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.terracotta,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              item.createdAt.toLocal().toString().split(' ')[0],
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textTertiary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Posted by ${item.authorName} (${item.authorRole.toUpperCase()})',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.body,
                          style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppTheme.textPrimary),
                        ),
                        if (isEvent && (item.eventDate != null || item.location != null)) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryTealLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.15)),
                            ),
                            child: Column(
                              children: [
                                if (item.eventDate != null)
                                  Row(
                                    children: [
                                      const Icon(Icons.event_available, size: 15, color: AppTheme.primaryTeal),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Date & Time: ${item.eventDate!.toLocal().toString().split('.')[0]}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTealDark),
                                      ),
                                    ],
                                  ),
                                if (item.location != null && item.location!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.place, size: 15, color: AppTheme.primaryTeal),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Location: ${item.location}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTealDark),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
