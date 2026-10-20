import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firebase_service.dart';
import '../../models/provider_profile.dart';
import '../../models/user_role.dart';
import '../../models/request_status.dart';
import '../../models/reservation.dart';
import '../../models/announcement.dart';
import '../../widgets/operating_hours_selector.dart';
import '../../utils/app_theme.dart';
import '../../widgets/boutique_animations.dart';

class VetHomeScreen extends StatefulWidget {
  const VetHomeScreen({super.key});

  @override
  State<VetHomeScreen> createState() => _VetHomeScreenState();
}

class _VetHomeScreenState extends State<VetHomeScreen> {
  final FirebaseService _auth = FirebaseService();
  int _currentIndex = 0;

  // Reservations tab filter: 'pending', 'accepted', 'history'
  String _reservationFilter = 'pending';

  String _formatVetName(String name) {
    final trimmed = name.trim();
    if (trimmed.toLowerCase().startsWith('dr.') || trimmed.toLowerCase().startsWith('dr ')) {
      return trimmed;
    }
    return 'Dr. $trimmed';
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.getCurrentUser();
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: Colors.white),
            SizedBox(width: 8),
            Text('PurrSync Vet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: AppTheme.vetAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Log Out',
            onPressed: () async {
              await _auth.signOut();
            },
          ),
        ],
      ),
      body: FutureBuilder<ProviderProfile?>(
        future: _auth.getProviderProfile(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.vetAccent));
          }
          final profile = snapshot.data;
          final rawName = profile?.displayName.isNotEmpty == true
              ? profile!.displayName
              : (user.displayName ?? 'Veterinarian');
          final formattedName = _formatVetName(rawName);

          return IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(user.uid, user.email ?? '', formattedName, profile),
              _buildReservationsTab(user.uid),
              _buildAnnouncementsTab(user.uid, formattedName),
              _buildProfileTab(profile, formattedName, user.email ?? '', user.uid),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppTheme.vetAccent,
        unselectedItemColor: AppTheme.textSecondary,
        backgroundColor: AppTheme.surface,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Reservations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            activeIcon: Icon(Icons.campaign),
            label: 'Announcements',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 0: HOME / OVERVIEW
  // ==========================================

  Widget _buildHomeTab(String vetId, String email, String displayName, ProviderProfile? profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: AppTheme.vetAccent.withValues(alpha: 0.12),
                    child: const Icon(Icons.health_and_safety, size: 30, color: AppTheme.vetAccent),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.vetAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'VET PORTAL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        displayName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Text(
                        email,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Real-time reservation stats stream
          StreamBuilder<List<Reservation>>(
            stream: _auth.getVetReservations(vetId),
            builder: (context, snapshot) {
              int pending = 0;
              int accepted = 0;
              int total = 0;
              List<Reservation> todayReservations = [];

              if (snapshot.hasData) {
                final list = snapshot.data!;
                total = list.length;
                pending = list.where((r) => r.status == RequestStatus.pending).length;
                accepted = list.where((r) => r.status == RequestStatus.accepted).length;

                final now = DateTime.now();
                todayReservations = list.where((r) {
                  return r.status == RequestStatus.accepted &&
                      r.requestedAt.year == now.year &&
                      r.requestedAt.month == now.month &&
                      r.requestedAt.day == now.day;
                }).toList();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildStatBox('Pending', pending.toString(), Icons.pending_actions, const Color(0xFFE5A038)),
                      const SizedBox(width: 12),
                      _buildStatBox('Accepted', accepted.toString(), Icons.event_available, AppTheme.primaryTeal),
                      const SizedBox(width: 12),
                      _buildStatBox('Total', total.toString(), Icons.list_alt, AppTheme.vetAccent),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Today's Schedule",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      if (todayReservations.isNotEmpty)
                        Text(
                          '${todayReservations.length} appointments',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (todayReservations.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderLight),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: const Center(
                        child: Text(
                          'No accepted appointments scheduled for today.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...todayReservations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final r = entry.value;
                      return FadeInSlide(
                        delay: Duration(milliseconds: 35 * idx),
                        child: BouncingScale(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.borderLight),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  color: AppTheme.primaryTealLight,
                                  child: const Icon(Icons.pets, color: AppTheme.primaryTeal, size: 20),
                                ),
                              ),
                              title: Text('${r.catName} (${r.visitType})', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              subtitle: Text('Owner: ${r.ownerName} • ${DateFormat('hh:mm a').format(r.requestedAt)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              trailing: const Icon(Icons.check_circle_outline, color: AppTheme.primaryTeal),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),

          const SizedBox(height: 24),
          const Text(
            'Provider Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _infoRow(Icons.location_city, 'City', profile?.city.isNotEmpty == true ? profile!.city : 'Not specified'),
                const Divider(color: AppTheme.dividerColor),
                _infoRow(Icons.home, 'Address', profile?.address.isNotEmpty == true ? profile!.address : 'Not specified'),
                const Divider(color: AppTheme.dividerColor),
                _infoRow(Icons.phone, 'Phone', profile?.phone.isNotEmpty == true ? profile!.phone : 'Not specified'),
                const Divider(color: AppTheme.dividerColor),
                _infoRow(Icons.access_time, 'Hours', profile?.hoursLabel.isNotEmpty == true ? profile!.hoursLabel : 'Not specified'),
                if (profile?.specialty?.isNotEmpty == true) ...[
                  const Divider(color: AppTheme.dividerColor),
                  _infoRow(Icons.star, 'Specialty', profile!.specialty!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Visit Types Handled',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          if (profile?.visitTypes.isNotEmpty == true)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile!.visitTypes.map((type) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.vetAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.vetAccent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: AppTheme.vetAccent),
                      const SizedBox(width: 5),
                      Text(
                        type,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.vetAccent),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else
            const Text(
              'No visit types specified yet.',
              style: TextStyle(color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, Color color) {
    final intVal = int.tryParse(value) ?? 0;
    return Expanded(
      child: BouncingScale(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              AnimatedCounterText(
                value: intVal,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: RESERVATIONS INBOX
  // ==========================================

  Widget _buildReservationsTab(String vetId) {
    return Column(
      children: [
        // Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              FilterChip(
                selected: _reservationFilter == 'pending',
                label: const Text('Pending'),
                selectedColor: const Color(0xFFFDEFD7),
                checkmarkColor: const Color(0xFFC77700),
                labelStyle: TextStyle(
                  color: _reservationFilter == 'pending' ? const Color(0xFF8A5200) : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _reservationFilter == 'pending' ? const Color(0xFFE5A038) : AppTheme.borderLight)),
                onSelected: (val) => setState(() => _reservationFilter = 'pending'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _reservationFilter == 'accepted',
                label: const Text('Accepted'),
                selectedColor: AppTheme.primaryTealLight,
                checkmarkColor: AppTheme.primaryTeal,
                labelStyle: TextStyle(
                  color: _reservationFilter == 'accepted' ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _reservationFilter == 'accepted' ? AppTheme.primaryTeal : AppTheme.borderLight)),
                onSelected: (val) => setState(() => _reservationFilter = 'accepted'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _reservationFilter == 'history',
                label: const Text('History'),
                selectedColor: const Color(0xFFE8ECEF),
                checkmarkColor: AppTheme.vetAccent,
                labelStyle: TextStyle(
                  color: _reservationFilter == 'history' ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _reservationFilter == 'history' ? AppTheme.vetAccent : AppTheme.borderLight)),
                onSelected: (val) => setState(() => _reservationFilter = 'history'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Reservation>>(
            stream: _auth.getVetReservations(vetId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text('Error loading reservations: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.vetAccent));
              }

              final all = snapshot.data!;
              final now = DateTime.now();
              final filtered = all.where((r) {
                final eff = effectiveStatus(
                  stored: r.status,
                  start: r.requestedAt,
                  end: r.requestedAt.add(const Duration(hours: 1)),
                  now: now,
                );
                if (_reservationFilter == 'pending') return eff == RequestStatus.pending;
                if (_reservationFilter == 'accepted') return eff == RequestStatus.accepted;
                return eff == RequestStatus.declined ||
                    eff == RequestStatus.completed ||
                    eff == RequestStatus.cancelled ||
                    eff == RequestStatus.expired;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox, size: 64, color: AppTheme.textTertiary),
                      const SizedBox(height: 12),
                      Text(
                        'No $_reservationFilter reservations',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final res = filtered[index];
                  return FadeInSlide(
                    delay: Duration(milliseconds: 35 * index),
                    child: BouncingScale(
                      child: _buildReservationCard(res),
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

  Widget _buildReservationCard(Reservation res) {
    final now = DateTime.now();
    final effStatus = effectiveStatus(
      stored: res.status,
      start: res.requestedAt,
      end: res.requestedAt.add(const Duration(hours: 1)),
      now: now,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 36,
                        height: 36,
                        color: AppTheme.vetAccent.withValues(alpha: 0.1),
                        child: const Icon(Icons.pets, color: AppTheme.vetAccent, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        res.catName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              effStatus.buildBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Owner: ${res.ownerName}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(res.visitType, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                DateFormat('EEE, MMM d • hh:mm a').format(res.requestedAt),
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
          if (res.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Notes: ${res.notes}', style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
            ),
          ],
          if (res.providerNote != null && res.providerNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD4D4)),
              ),
              child: Text(
                'Your note: ${res.providerNote}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC92A2A)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Actions
          if (effStatus == RequestStatus.pending) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showDeclineDialog(res.id, isBooking: false),
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFFD32F2F)),
                  label: const Text('Decline', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD32F2F)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _updateReservationStatus(res.id, RequestStatus.accepted),
                  icon: const Icon(Icons.check, size: 16, color: Colors.white),
                  label: const Text('Accept', style: TextStyle(color: Colors.white, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ] else if (effStatus == RequestStatus.accepted) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showDeclineDialog(res.id, isBooking: false),
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFD32F2F)),
                  label: const Text('Cancel / Decline', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD32F2F)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _updateReservationStatus(res.id, RequestStatus.completed),
                  icon: const Icon(Icons.done_all, size: 16, color: Colors.white),
                  label: const Text('Mark Completed', style: TextStyle(color: Colors.white, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.vetAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _updateReservationStatus(String id, RequestStatus newStatus, {String? note}) async {
    try {
      await _auth.respondToReservation(id, newStatus, providerNote: note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reservation updated to ${newStatus.label}')),
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating reservation: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeclineDialog(String id, {required bool isBooking}) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Decline Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a reason or note for the cat owner (optional):'),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Fully booked at this hour, please select another time.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () {
                final note = noteController.text.trim();
                Navigator.pop(dialogCtx);
                _updateReservationStatus(
                  id,
                  RequestStatus.declined,
                  note: note.isNotEmpty ? note : null,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // TAB 2: ANNOUNCEMENTS & EVENTS
  // ==========================================

  Widget _buildAnnouncementsTab(String vetId, String vetName) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<Announcement>>(
        stream: _auth.getMyAnnouncements(vetId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading announcements: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.vetAccent));
          }

          final announcements = snapshot.data!;
          if (announcements.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.campaign_outlined, size: 72, color: AppTheme.textTertiary),
                  const SizedBox(height: 16),
                  const Text('No announcements posted yet', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Share updates, vaccine drives, and clinic events!', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _openAnnouncementDialog(vetId, vetName),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Create Announcement', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.vetAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final item = announcements[index];
              return FadeInSlide(
                delay: Duration(milliseconds: 35 * index),
                child: BouncingScale(
                  child: _buildAnnouncementCard(item, vetId, vetName),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAnnouncementDialog(vetId, vetName),
        backgroundColor: AppTheme.vetAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildAnnouncementCard(Announcement item, String vetId, String vetName) {
    final isEvent = item.type == 'event';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isEvent ? const Color(0xFFF7ECF8) : AppTheme.primaryTealLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isEvent ? const Color(0xFFD8B4E2) : const Color(0xFFB3D9D5)),
                ),
                child: Text(
                  isEvent ? 'EVENT / DRIVE' : 'UPDATE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isEvent ? const Color(0xFF7B2D85) : AppTheme.primaryTealDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: item.published ? const Color(0xFFE8F5E9) : const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.published ? 'Published' : 'Draft',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.published ? const Color(0xFF2E7D32) : AppTheme.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: AppTheme.textSecondary),
                onPressed: () => _openAnnouncementDialog(vetId, vetName, existing: item),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 18, color: Color(0xFFD32F2F)),
                onPressed: () => _confirmDeleteAnnouncement(item.id),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(item.body, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4)),
          if (isEvent && item.eventDate != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.event, size: 16, color: Color(0xFF7B2D85)),
                const SizedBox(width: 6),
                Text(
                  DateFormat('EEE, MMM d, yyyy • hh:mm a').format(item.eventDate!),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF7B2D85), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          if (item.location != null && item.location!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(item.location!, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _confirmDeleteAnnouncement(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: const Text('Are you sure you want to permanently delete this announcement?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _auth.deleteAnnouncement(id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Announcement deleted')),
                  );
                }
              } on AppException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openAnnouncementDialog(String vetId, String vetName, {Announcement? existing}) {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    final locationCtrl = TextEditingController(text: existing?.location ?? '');
    String type = existing?.type ?? 'news';
    DateTime? eventDate = existing?.eventDate;
    TimeOfDay? eventTime = eventDate != null ? TimeOfDay.fromDateTime(eventDate) : null;
    DateTime? expiresAt = existing?.expiresAt;
    bool published = existing?.published ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            existing == null ? 'Create Announcement' : 'Edit Announcement',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(sheetCtx),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Type Selector
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Update / News'),
                            selected: type == 'news',
                            onSelected: (val) {
                              if (val) setSheetState(() => type = 'news');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Event / Drive'),
                            selected: type == 'event',
                            onSelected: (val) {
                              if (val) setSheetState(() => type = 'event');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a title' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: bodyCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Details / Content *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter content' : null,
                      ),
                      const SizedBox(height: 12),

                      if (type == 'event') ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: eventDate ?? DateTime.now(),
                                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setSheetState(() => eventDate = picked);
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: Text(
                                  eventDate == null
                                      ? 'Pick Date'
                                      : DateFormat('MMM d, yyyy').format(eventDate!),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: eventTime ?? TimeOfDay.now(),
                                    initialEntryMode: TimePickerEntryMode.dialOnly,
                                  );
                                  if (picked != null) {
                                    setSheetState(() => eventTime = picked);
                                  }
                                },
                                icon: const Icon(Icons.access_time, size: 16),
                                label: Text(
                                  eventTime == null
                                      ? 'Pick Time'
                                      : eventTime!.format(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: locationCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Event Location',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: sheetCtx,
                            initialDate: expiresAt ?? now.add(const Duration(days: 7)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setSheetState(() => expiresAt = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Visible Until (optional)',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.timer_outlined),
                            suffixIcon: expiresAt != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setSheetState(() => expiresAt = null),
                                  )
                                : null,
                          ),
                          child: Text(
                            expiresAt != null
                                ? DateFormat('EEE, MMM d, yyyy').format(expiresAt!)
                                : 'Always visible (no expiry)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        title: const Text('Published'),
                        subtitle: const Text('Visible to cat owners immediately'),
                        value: published,
                        onChanged: (val) => setSheetState(() => published = val),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;

                            DateTime? finalEventDate;
                            if (type == 'event') {
                              final d = eventDate ?? DateTime.now();
                              final t = eventTime ?? const TimeOfDay(hour: 9, minute: 0);
                              finalEventDate = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                            }

                            final announcement = Announcement(
                              id: existing?.id ?? '',
                              authorId: vetId,
                              authorRole: UserRole.vet.toValue(),
                              authorName: vetName,
                              type: type,
                              title: titleCtrl.text.trim(),
                              body: bodyCtrl.text.trim(),
                              eventDate: finalEventDate,
                              location: locationCtrl.text.trim().isNotEmpty ? locationCtrl.text.trim() : null,
                              expiresAt: expiresAt,
                              published: published,
                              createdAt: existing?.createdAt ?? DateTime.now(),
                              updatedAt: DateTime.now(),
                            );

                            try {
                              if (existing == null) {
                                await _auth.addAnnouncement(announcement);
                              } else {
                                await _auth.updateAnnouncement(announcement);
                              }
                              if (context.mounted) {
                                Navigator.pop(sheetCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(existing == null ? 'Announcement posted!' : 'Announcement updated!')),
                                );
                              }
                            } on AppException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.vetAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            existing == null ? 'Post Announcement' : 'Save Changes',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 3: PROFILE & EDIT PROFILE
  // ==========================================

  Widget _buildProfileTab(ProviderProfile? profile, String displayName, String email, String uid) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 88,
              height: 88,
              color: AppTheme.vetAccent.withValues(alpha: 0.12),
              child: const Icon(Icons.medical_services, size: 44, color: AppTheme.vetAccent),
            ),
          ),
          const SizedBox(height: 14),
          Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(email, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openEditProfileSheet(profile, uid, email),
              icon: const Icon(Icons.edit, color: Colors.white, size: 18),
              label: const Text('Edit Provider Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.vetAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),

          _buildProfileTile(Icons.badge_outlined, 'Account Role', 'Veterinarian'),
          const SizedBox(height: 10),
          _buildProfileTile(Icons.home_outlined, 'Address', profile?.address.isNotEmpty == true ? profile!.address : 'Not set'),
          const SizedBox(height: 10),
          _buildProfileTile(Icons.location_on_outlined, 'City / Location', profile?.city.isNotEmpty == true ? profile!.city : 'Not set'),
          const SizedBox(height: 10),
          _buildProfileTile(Icons.phone_outlined, 'Phone Number', profile?.phone.isNotEmpty == true ? profile!.phone : 'Not set'),
          const SizedBox(height: 10),
          _buildProfileTile(Icons.access_time, 'Operating Hours', profile?.hoursLabel.isNotEmpty == true ? profile!.hoursLabel : 'Not set'),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _auth.signOut();
              },
              icon: const Icon(Icons.logout, color: Color(0xFFD32F2F)),
              label: const Text('Log Out', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD32F2F)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(IconData icon, String title, String subtitle) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.vetAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.vetAccent, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      ),
    );
  }

  void _openEditProfileSheet(ProviderProfile? profile, String uid, String email) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: profile?.displayName ?? '');
    final addressCtrl = TextEditingController(text: profile?.address ?? '');
    final cityCtrl = TextEditingController(text: profile?.city ?? '');
    final phoneCtrl = TextEditingController(text: profile?.phone ?? '');
    final bioCtrl = TextEditingController(text: profile?.bio ?? '');
    final specialtyCtrl = TextEditingController(text: profile?.specialty ?? '');

    String openT = profile?.openTime ?? '08:00';
    String closeT = profile?.closeTime ?? '18:00';
    List<int> openD = profile?.openDays.isNotEmpty == true ? List.from(profile!.openDays) : [1, 2, 3, 4, 5, 6];

    List<String> selectedVisitTypes = profile?.visitTypes.isNotEmpty == true
        ? List.from(profile!.visitTypes)
        : ['Consultation', 'Vaccination', 'Checkup'];

    const availableVisitTypes = [
      'Consultation',
      'Vaccination',
      'General Checkup',
      'Emergency',
      'Dental',
      'Surgery',
      'Deworming',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Edit Provider Profile',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Display Name *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone Number *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Phone is required' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'City is required' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(labelText: 'Address *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Address is required' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: specialtyCtrl,
                        decoration: const InputDecoration(labelText: 'Specialty (e.g. Feline Internal Medicine)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: bioCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Bio / Description', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),

                      const Text('Visit Types Handled', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: availableVisitTypes.map((vt) {
                          final isSelected = selectedVisitTypes.contains(vt);
                          return FilterChip(
                            label: Text(vt),
                            selected: isSelected,
                            selectedColor: AppTheme.vetAccent.withValues(alpha: 0.15),
                            checkmarkColor: AppTheme.vetAccent,
                            labelStyle: TextStyle(
                              color: isSelected ? AppTheme.vetAccent : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? AppTheme.vetAccent : AppTheme.borderLight)),
                            onSelected: (val) {
                              setSheetState(() {
                                if (val) {
                                  selectedVisitTypes.add(vt);
                                } else {
                                  selectedVisitTypes.remove(vt);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      const Text('Operating Hours & Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      OperatingHoursSelector(
                        openTime: openT,
                        closeTime: closeT,
                        openDays: openD,
                        onOpenTimeChanged: (val) => setSheetState(() => openT = val),
                        onCloseTimeChanged: (val) => setSheetState(() => closeT = val),
                        onOpenDaysChanged: (val) => setSheetState(() => openD = val),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;

                            final updatedProfile = ProviderProfile(
                              id: uid,
                              role: UserRole.vet,
                              displayName: nameCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                              city: cityCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              bio: bioCtrl.text.trim(),
                              specialty: specialtyCtrl.text.trim().isNotEmpty ? specialtyCtrl.text.trim() : null,
                              visitTypes: selectedVisitTypes,
                              openTime: openT,
                              closeTime: closeT,
                              openDays: openD,
                              hoursLabel: ProviderProfile.computeHoursLabel(openD, openT, closeT),
                              createdAt: profile?.createdAt ?? DateTime.now(),
                              updatedAt: DateTime.now(),
                            );

                            try {
                              await _auth.saveProviderProfile(updatedProfile);
                              if (context.mounted) {
                                Navigator.pop(sheetCtx);
                                setState(() {}); // Refresh future
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Profile updated successfully!')),
                                );
                              }
                            } on AppException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.vetAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Save Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.vetAccent),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }
}
