import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../models/reservation.dart';
import '../../models/booking.dart';
import '../../models/request_status.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/map_utils.dart';
import '../../widgets/boutique_animations.dart';
import 'reservation_form_screen.dart';
import 'booking_form_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _db = FirebaseService();

  // Filter state per tab: 'active' (default) or 'history'
  String _reservationFilter = 'active';
  String _bookingFilter = 'active';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isActiveStatus(RequestStatus effStatus) {
    return effStatus == RequestStatus.pending || effStatus == RequestStatus.accepted;
  }

  Widget _buildFilterPills({
    required String selectedFilter,
    required int activeCount,
    required int historyCount,
    required ValueChanged<String> onSelect,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        children: [
          _buildPillTab(
            label: 'Active',
            count: activeCount,
            icon: Icons.event_available_outlined,
            isSelected: selectedFilter == 'active',
            onTap: () => onSelect('active'),
          ),
          const SizedBox(width: 6),
          _buildPillTab(
            label: 'History / Archive',
            count: historyCount,
            icon: Icons.inventory_2_outlined,
            isSelected: selectedFilter == 'history',
            onTap: () => onSelect('history'),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab({
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppTheme.borderLight.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyFilterState({
    required bool isActiveTab,
    required String activeSubtitle,
    required String historySubtitle,
  }) {
    return BouncyPawEmptyState(
      title: isActiveTab ? 'No upcoming appointments' : 'No archived appointments yet',
      subtitle: isActiveTab ? activeSubtitle : historySubtitle,
      badgeIcon: isActiveTab ? Icons.event_available_outlined : Icons.inventory_2_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _db.getCurrentUser();
    if (user == null) {
      return const Center(child: Text('Not signed in'));
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('My Appointments', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: AppTheme.ownerAccent,
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
            Tab(icon: Icon(Icons.calendar_today_outlined), text: 'Consultations'),
            Tab(icon: Icon(Icons.local_hospital_outlined), text: 'Clinic Services'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReservationsTab(user.uid),
          _buildBookingsTab(user.uid),
        ],
      ),
    );
  }

  // ============ RESERVATIONS TAB (VET) ============
  Widget _buildReservationsTab(String ownerId) {
    return StreamBuilder<List<Reservation>>(
      stream: _db.getOwnerReservations(ownerId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text('Could not load reservations.\n${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SkeletonCardList(itemCount: 3);
        }
        final list = snapshot.data!;
        _db.syncCompletedClinicalEMRForOwner(reservations: list);
        final now = DateTime.now();
        if (!kIsWeb) {
          for (final r in list) {
            if (r.status == RequestStatus.accepted && r.requestedAt.isAfter(now)) {
              NotificationService.scheduleAppointmentReminder(
                r.id,
                'Appointment with ${r.vetName} for ${r.catName}',
                r.requestedAt,
              );
            } else {
              NotificationService.cancelReminder(r.id);
            }
          }
        }

        final activeList = <Reservation>[];
        final historyList = <Reservation>[];
        for (final r in list) {
          final isEmergency = r.visitType.toLowerCase().contains('emergency');
          final eff = effectiveStatus(
            stored: r.status,
            start: isEmergency ? r.requestedAt.add(const Duration(hours: 12)) : r.requestedAt,
            end: r.requestedAt.add(const Duration(hours: 1)),
            now: now,
          );
          if (_isActiveStatus(eff)) {
            activeList.add(r);
          } else {
            historyList.add(r);
          }
        }

        // Active sorting: Emergency pinned to top, then closest upcoming date
        activeList.sort((a, b) {
          final aEmg = a.visitType.toLowerCase().contains('emergency');
          final bEmg = b.visitType.toLowerCase().contains('emergency');
          if (aEmg != bEmg) return aEmg ? -1 : 1;
          return a.requestedAt.compareTo(b.requestedAt);
        });

        // History sorting: newest first
        historyList.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

        final isShowingActive = _reservationFilter == 'active';
        final displayedList = isShowingActive ? activeList : historyList;

        return Column(
          children: [
            _buildFilterPills(
              selectedFilter: _reservationFilter,
              activeCount: activeList.length,
              historyCount: historyList.length,
              onSelect: (val) => setState(() => _reservationFilter = val),
            ),
            Expanded(
              child: displayedList.isEmpty
                  ? _buildEmptyFilterState(
                      isActiveTab: isShowingActive,
                      activeSubtitle: 'Explore the Discover tab to find a veterinarian and schedule a consultation.',
                      historySubtitle: 'Completed, declined, and cancelled vet consultations will appear here.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: displayedList.length,
                      itemBuilder: (context, index) {
                        final r = displayedList[index];
                        return FadeInSlide(
                          delay: Duration(milliseconds: 35 * index),
                          child: BouncingScale(
                            child: _buildReservationCard(r),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReservationCard(Reservation r) {
    final now = DateTime.now();
    final isEmergency = r.visitType.toLowerCase().contains('emergency');
    final effStatus = effectiveStatus(
      stored: r.status,
      start: isEmergency ? r.requestedAt.add(const Duration(hours: 12)) : r.requestedAt,
      end: r.requestedAt.add(const Duration(hours: 1)),
      now: now,
    );
    final dateStr = r.requestedAt.toLocal().toString().split(' ')[0];
    final timeStr = TimeOfDay(hour: r.requestedAt.hour, minute: r.requestedAt.minute).format(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isEmergency && _isActiveStatus(effStatus) ? const Color(0xFFFFFAFA) : AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isEmergency && _isActiveStatus(effStatus) ? Colors.red.shade400 : AppTheme.borderLight,
          width: isEmergency && _isActiveStatus(effStatus) ? 1.5 : 1.0,
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.vetName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, color: AppTheme.textPrimaryColor(context)),
                  ),
                ),
                effStatus.buildBadge(),
              ],
            ),
            AppointmentStatusStepper(status: effStatus),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isEmergency ? const Color(0xFFFFEBEE) : AppTheme.primaryTealLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEmergency ? '🚨 ${r.visitType}' : r.visitType,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      color: isEmergency ? Colors.red.shade800 : AppTheme.primaryTealDark,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🐾 ${r.catName} (${r.catBreed.isNotEmpty ? r.catBreed : 'Cat'})',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ),
                if (r.queueNumber != null && r.queueNumber!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTealDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Queue: ${r.queueNumber}',
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                if (r.checkedInAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.statusSafe.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '🟢 Checked-In at Reception',
                      style: TextStyle(fontSize: 11, color: AppTheme.statusSafe, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule, size: 15, color: AppTheme.primaryTeal),
                const SizedBox(width: 6),
                Text(
                  '$dateStr at $timeStr',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Notes: ${r.notes}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
            ],
            if (r.providerNote != null && r.providerNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (effStatus == RequestStatus.declined || r.status == RequestStatus.declined)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFC62828), size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Decline Reason: ${r.providerNote}',
                          style: const TextStyle(color: Color(0xFFC62828), fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTealLight.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.medical_information_outlined, color: AppTheme.primaryTealDark, size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Clinical Notes: ${r.providerNote}',
                          style: const TextStyle(color: AppTheme.primaryTealDark, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Open in Google Maps for Accepted Appointments
                if (effStatus == RequestStatus.accepted) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final prov = await _db.getProviderProfile(r.vetId);
                      final addr = (prov != null && prov.address.isNotEmpty)
                          ? '${prov.address}, ${prov.city}'
                          : r.vetName;
                      if (mounted) {
                        MapUtils.openDirections(
                          destinationAddress: addr,
                          clinicName: r.vetName,
                          context: context,
                        );
                      }
                    },
                    icon: const Icon(Icons.directions, size: 14, color: Colors.white),
                    label: const Text('Open in Google Maps', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Edit details while pending
                if (effStatus == RequestStatus.pending) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final vetProfile = await _db.getProviderProfile(r.vetId);
                      if (vetProfile != null && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReservationFormScreen(
                              vet: vetProfile,
                              existingReservation: r,
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryTeal,
                      side: const BorderSide(color: AppTheme.primaryTeal),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Cancel while pending or accepted
                if (effStatus == RequestStatus.pending || effStatus == RequestStatus.accepted) ...[
                  OutlinedButton.icon(
                    onPressed: () => _confirmCancelReservation(r),
                    icon: const Icon(Icons.cancel_outlined, size: 15, color: Color(0xFFC62828)),
                    label: const Text('Cancel', style: TextStyle(color: Color(0xFFC62828))),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      side: const BorderSide(color: Color(0xFFEF9A9A)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
                // Delete when closed, cancelled, declined, or expired
                if (effStatus == RequestStatus.cancelled || effStatus == RequestStatus.declined || effStatus == RequestStatus.expired || effStatus == RequestStatus.completed) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
                    tooltip: 'Delete Record',
                    onPressed: () => _confirmDeleteReservation(r),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancelReservation(Reservation r) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel Reservation?'),
        content: Text('Are you sure you want to cancel your appointment with ${r.vetName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.cancelReservation(r.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reservation cancelled')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteReservation(Reservation r) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Reservation?'),
        content: const Text('This will permanently remove this closed reservation record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.deleteReservation(r.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reservation removed')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ============ BOOKINGS TAB (CLINIC) ============
  Widget _buildBookingsTab(String ownerId) {
    return StreamBuilder<List<Booking>>(
      stream: _db.getOwnerBookings(ownerId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text('Could not load bookings.\n${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () => setState(() {}), child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SkeletonCardList(itemCount: 3);
        }
        final list = snapshot.data!;
        _db.syncCompletedClinicalEMRForOwner(bookings: list);
        final now = DateTime.now();
        if (!kIsWeb) {
          for (final b in list) {
            if (b.status == RequestStatus.accepted && b.scheduledAt.isAfter(now)) {
              NotificationService.scheduleAppointmentReminder(
                b.id,
                'Booking at ${b.clinicName} for ${b.catName}',
                b.scheduledAt,
              );
            } else {
              NotificationService.cancelReminder(b.id);
            }
          }
        }

        final activeList = <Booking>[];
        final historyList = <Booking>[];
        for (final b in list) {
          final eff = effectiveStatus(
            stored: b.status,
            start: b.scheduledAt,
            end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
            now: now,
          );
          if (_isActiveStatus(eff)) {
            activeList.add(b);
          } else {
            historyList.add(b);
          }
        }

        // Active sorting: Emergency pinned to top, then closest upcoming date
        activeList.sort((a, b) {
          final aEmg = a.serviceName.toLowerCase().contains('emergency');
          final bEmg = b.serviceName.toLowerCase().contains('emergency');
          if (aEmg != bEmg) return aEmg ? -1 : 1;
          return a.scheduledAt.compareTo(b.scheduledAt);
        });

        // History sorting: newest first
        historyList.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

        final isShowingActive = _bookingFilter == 'active';
        final displayedList = isShowingActive ? activeList : historyList;

        return Column(
          children: [
            _buildFilterPills(
              selectedFilter: _bookingFilter,
              activeCount: activeList.length,
              historyCount: historyList.length,
              onSelect: (val) => setState(() => _bookingFilter = val),
            ),
            Expanded(
              child: displayedList.isEmpty
                  ? _buildEmptyFilterState(
                      isActiveTab: isShowingActive,
                      activeSubtitle: 'Explore clinic services in Discover to book grooming, checkups, or vaccinations.',
                      historySubtitle: 'Completed, declined, and cancelled clinic service bookings will appear here.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: displayedList.length,
                      itemBuilder: (context, index) {
                        final b = displayedList[index];
                        return FadeInSlide(
                          delay: Duration(milliseconds: 35 * index),
                          child: BouncingScale(
                            child: _buildBookingCard(b),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBookingCard(Booking b) {
    final now = DateTime.now();
    final effStatus = effectiveStatus(
      stored: b.status,
      start: b.scheduledAt,
      end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
      now: now,
    );
    final dateStr = b.scheduledAt.toLocal().toString().split(' ')[0];
    final timeStr = TimeOfDay(hour: b.scheduledAt.hour, minute: b.scheduledAt.minute).format(context);

    return Container(
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
                Expanded(
                  child: Text(
                    b.clinicName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, color: AppTheme.textPrimaryColor(context)),
                  ),
                ),
                effStatus.buildBadge(),
              ],
            ),
            AppointmentStatusStepper(status: effStatus),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTealLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${b.serviceName} • ₱${b.servicePrice.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppTheme.primaryTealDark),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🐾 ${b.catName} (${b.catBreed.isNotEmpty ? b.catBreed : 'Cat'})',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ),
                if (b.queueNumber != null && b.queueNumber!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTealDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Queue: ${b.queueNumber}',
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                if (b.checkedInAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.statusSafe.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '🟢 Checked-In at Reception',
                      style: TextStyle(fontSize: 11, color: AppTheme.statusSafe, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule, size: 15, color: AppTheme.primaryTeal),
                const SizedBox(width: 6),
                Text(
                  '$dateStr at $timeStr (${b.serviceDurationMinutes} mins)',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (b.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Notes: ${b.notes}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
            ],
            if (b.providerNote != null && b.providerNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (effStatus == RequestStatus.declined || b.status == RequestStatus.declined)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFC62828), size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Decline Reason: ${b.providerNote}',
                          style: const TextStyle(color: Color(0xFFC62828), fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTealLight.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.medical_information_outlined, color: AppTheme.primaryTealDark, size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Clinical Notes: ${b.providerNote}',
                          style: const TextStyle(color: AppTheme.primaryTealDark, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Open in Google Maps for Accepted Appointments
                if (effStatus == RequestStatus.accepted) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final prov = await _db.getProviderProfile(b.clinicId);
                      final addr = (prov != null && prov.address.isNotEmpty)
                          ? '${prov.address}, ${prov.city}'
                          : b.clinicName;
                      if (mounted) {
                        MapUtils.openDirections(
                          destinationAddress: addr,
                          clinicName: b.clinicName,
                          context: context,
                        );
                      }
                    },
                    icon: const Icon(Icons.directions, size: 14, color: Colors.white),
                    label: const Text('Open in Google Maps', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Edit details while pending
                if (effStatus == RequestStatus.pending) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final clinicProfile = await _db.getProviderProfile(b.clinicId);
                      if (clinicProfile != null && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BookingFormScreen(
                              clinic: clinicProfile,
                              existingBooking: b,
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryTeal,
                      side: const BorderSide(color: AppTheme.primaryTeal),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Cancel while pending or accepted
                if (effStatus == RequestStatus.pending || effStatus == RequestStatus.accepted) ...[
                  OutlinedButton.icon(
                    onPressed: () => _confirmCancelBooking(b),
                    icon: const Icon(Icons.cancel_outlined, size: 15, color: Color(0xFFC62828)),
                    label: const Text('Cancel', style: TextStyle(color: Color(0xFFC62828))),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      side: const BorderSide(color: Color(0xFFEF9A9A)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
                // Delete when closed, cancelled, declined, or expired
                if (effStatus == RequestStatus.cancelled || effStatus == RequestStatus.declined || effStatus == RequestStatus.expired || effStatus == RequestStatus.completed) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
                    tooltip: 'Delete Record',
                    onPressed: () => _confirmDeleteBooking(b),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancelBooking(Booking b) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Text('Are you sure you want to cancel your booking with ${b.clinicName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.cancelBooking(b.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBooking(Booking b) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Booking?'),
        content: const Text('This will permanently remove this closed booking record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.deleteBooking(b.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking removed')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
