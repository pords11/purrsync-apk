import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firebase_service.dart';
import '../../models/provider_profile.dart';
import '../../models/request_status.dart';
import '../../models/reservation.dart';
import '../../models/booking.dart';
import '../../models/service_offering.dart';
import '../../models/announcement.dart';
import '../../models/user_role.dart';
import '../../widgets/operating_hours_selector.dart';
import '../../widgets/boutique_animations.dart';
import '../../widgets/vet_qr_scanner_dialog.dart';
import '../../widgets/clinical_emr_dialog.dart';
import '../../utils/app_theme.dart';
import '../../utils/map_utils.dart';

/// Unified "Vet / Clinic" Provider Dashboard combining consultation reservations,
/// service bookings, services catalog CRUD, community announcements, and provider profile.
class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  final FirebaseService _auth = FirebaseService();
  int _currentIndex = 0;

  // Appointments filter state
  String _appointmentTypeFilter = 'all'; // 'all', 'reservations', 'bookings'
  String _appointmentStatusFilter = 'pending'; // 'pending', 'accepted', 'history'

  // Live notification badge & emergency alert tracking
  StreamSubscription<List<Reservation>>? _resSub;
  StreamSubscription<List<Booking>>? _bookSub;
  List<Reservation> _latestReservations = [];
  List<Booking> _latestBookings = [];
  int _pendingAppointmentsCount = 0;
  bool _hasPendingEmergency = false;
  final Set<String> _acknowledgedEmergencyIds = {};
  bool _isShowingEmergencyDialog = false;

  // Automated Smart Queue & Reception Engine state
  bool _autoAcceptEnabled = true;
  bool _isAutoProcessingQueue = false;
  final Set<String> _autoProcessedIds = {};
  String _cachedProviderName = 'Veterinary Clinic';

  @override
  void initState() {
    super.initState();
    final user = _auth.getCurrentUser();
    if (user != null) {
      _resSub = _auth.getVetReservations(user.uid).listen((list) {
        if (!mounted) return;
        _latestReservations = list;
        _recomputeBadgesAndAlerts();
      });
      _bookSub = _auth.getClinicBookings(user.uid).listen((list) {
        if (!mounted) return;
        _latestBookings = list;
        _recomputeBadgesAndAlerts();
      });
    }
  }

  void _recomputeBadgesAndAlerts() {
    final now = DateTime.now();
    int pendingCount = 0;
    bool hasEmergency = false;
    Reservation? unacknowledgedEmergency;

    for (final r in _latestReservations) {
      final eff = effectiveStatus(
        stored: r.status,
        start: r.requestedAt,
        end: r.requestedAt.add(const Duration(hours: 1)),
        now: now,
      );
      final isEmergency = r.visitType.toLowerCase().contains('emergency');
      if (eff == RequestStatus.pending || (isEmergency && r.status == RequestStatus.pending)) {
        pendingCount++;
        if (isEmergency) {
          hasEmergency = true;
          if (!_acknowledgedEmergencyIds.contains(r.id)) {
            unacknowledgedEmergency ??= r;
          }
        }
      }
    }

    for (final b in _latestBookings) {
      final eff = effectiveStatus(
        stored: b.status,
        start: b.scheduledAt,
        end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
        now: now,
      );
      if (eff == RequestStatus.pending) {
        pendingCount++;
        if (b.serviceName.toLowerCase().contains('emergency')) {
          hasEmergency = true;
        }
      }
    }

    if (pendingCount != _pendingAppointmentsCount || hasEmergency != _hasPendingEmergency) {
      setState(() {
        _pendingAppointmentsCount = pendingCount;
        _hasPendingEmergency = hasEmergency;
      });
    }

    if (unacknowledgedEmergency != null && !_isShowingEmergencyDialog && mounted) {
      _acknowledgedEmergencyIds.add(unacknowledgedEmergency.id);
      _triggerUrgentEmergencyDialog(unacknowledgedEmergency);
    }

    // Live Automated Queue Engine: auto-accept non-conflicting incoming requests when enabled
    if (_autoAcceptEnabled && pendingCount > 0 && !_isAutoProcessingQueue) {
      final hasNewPending = _latestReservations.any(
            (r) => r.status == RequestStatus.pending && !_autoProcessedIds.contains(r.id),
          ) ||
          _latestBookings.any(
            (b) => b.status == RequestStatus.pending && !_autoProcessedIds.contains(b.id),
          );
      if (hasNewPending) {
        for (final r in _latestReservations) {
          if (r.status == RequestStatus.pending) _autoProcessedIds.add(r.id);
        }
        for (final b in _latestBookings) {
          if (b.status == RequestStatus.pending) _autoProcessedIds.add(b.id);
        }
        final user = _auth.getCurrentUser();
        if (user != null) {
          _runSilentAutoAccept(user.uid, _cachedProviderName);
        }
      }
    }
  }

  Future<void> _runSilentAutoAccept(String providerId, String providerName) async {
    if (_isAutoProcessingQueue) return;
    _isAutoProcessingQueue = true;
    try {
      final res = await _auth.autoProcessPendingAppointments(
        providerId: providerId,
        providerName: providerName,
      );
      final accepted = res['acceptedCount'] ?? 0;
      if (accepted > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Smart Queue Auto-Accepted $accepted conflict-free appointment(s) & assigned queue numbers!'),
            backgroundColor: AppTheme.primaryTeal,
          ),
        );
      }
    } catch (_) {
    } finally {
      _isAutoProcessingQueue = false;
    }
  }

  Future<void> _triggerAutoProcessPendingQueue(String providerId, String providerName) async {
    if (_isAutoProcessingQueue) return;
    setState(() => _isAutoProcessingQueue = true);
    try {
      final res = await _auth.autoProcessPendingAppointments(
        providerId: providerId,
        providerName: providerName,
      );
      final accepted = res['acceptedCount'] ?? 0;
      final conflicts = res['conflictCount'] ?? 0;
      if (!mounted) return;
      if (accepted > 0) {
        await showPurrSyncSuccessOverlay(
          context,
          title: 'Auto-Processed $accepted Patient(s)!',
          subtitle: conflicts > 0
              ? 'Queue numbers assigned. $conflicts conflicting slot(s) held for manual review.'
              : 'All valid appointments auto-confirmed & assigned live Queue Numbers.',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              conflicts > 0
                  ? 'No conflict-free pending slots to auto-accept ($conflicts time conflict(s) detected).'
                  : 'All pending appointments are already processed!',
            ),
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
    } finally {
      if (mounted) setState(() => _isAutoProcessingQueue = false);
    }
  }

  void _openQRScanner(String providerId, String providerName) {
    showDialog(
      context: context,
      builder: (_) => VetQRScannerDialog(
        providerId: providerId,
        providerName: providerName,
      ),
    );
  }

  void _callNextPatientAndOpenEMR(String providerName) {
    final now = DateTime.now();
    final activeItems = <_UnifiedAppointmentItem>[];

    for (final r in _latestReservations) {
      final isEmergency = r.visitType.toLowerCase().contains('emergency');
      final eff = effectiveStatus(
        stored: r.status,
        start: isEmergency ? r.requestedAt.add(const Duration(hours: 12)) : r.requestedAt,
        end: r.requestedAt.add(const Duration(hours: 1)),
        now: now,
      );
      if (eff == RequestStatus.accepted || (isEmergency && r.status == RequestStatus.pending)) {
        activeItems.add(_UnifiedAppointmentItem.fromReservation(r, eff));
      }
    }

    for (final b in _latestBookings) {
      final eff = effectiveStatus(
        stored: b.status,
        start: b.scheduledAt,
        end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
        now: now,
      );
      if (eff == RequestStatus.accepted) {
        activeItems.add(_UnifiedAppointmentItem.fromBooking(b, eff));
      }
    }

    if (activeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active/accepted patients in the queue right now. Scan a patient QR or accept a request first.'),
          backgroundColor: AppTheme.primaryTeal,
        ),
      );
      return;
    }

    // Priority sort: 1) Emergency -> 2) Checked-In via QR -> 3) Earliest scheduled time
    activeItems.sort((a, b) {
      if (a.isEmergency != b.isEmergency) return a.isEmergency ? -1 : 1;
      if (a.isCheckedIn != b.isCheckedIn) return a.isCheckedIn ? -1 : 1;
      return a.dateTime.compareTo(b.dateTime);
    });

    final nextItem = activeItems.first;
    if (nextItem.isReservation) {
      _showCompleteReservationDialog(nextItem.reservation!, providerName: providerName);
    } else {
      _showCompleteBookingDialog(nextItem.booking!, providerName: providerName);
    }
  }

  void _triggerUrgentEmergencyDialog(Reservation emergencyRes) {
    _isShowingEmergencyDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isShowingEmergencyDialog = false;
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.red.shade700, width: 2),
          ),
          backgroundColor: const Color(0xFFFFF8F8),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🚨 URGENT TRIAGE: Emergency Request for ${emergencyRes.catName}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Owner: ${emergencyRes.ownerName} • Cat: ${emergencyRes.catName} (${emergencyRes.catBreed})',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Requested Time: ${DateFormat('MMM d, yyyy • hh:mm a').format(emergencyRes.requestedAt)}',
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade800, fontWeight: FontWeight.w600),
              ),
              if (emergencyRes.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reported Emergency Symptoms:',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        emergencyRes.notes,
                        style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
              },
              child: const Text('Dismiss', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                if (mounted) {
                  setState(() {
                    _currentIndex = 1;
                    _appointmentTypeFilter = 'all';
                    _appointmentStatusFilter = 'pending';
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Review Now', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ).whenComplete(() {
        _isShowingEmergencyDialog = false;
      });
    });
  }

  @override
  void dispose() {
    _resSub?.cancel();
    _bookSub?.cancel();
    super.dispose();
  }

  String _formatProviderName(String name) {
    return name.trim();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.getCurrentUser();
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: Colors.white),
            SizedBox(width: 8),
            Text('PurrSync Provider', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
          ],
        ),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Scan Patient QR Check-In',
            onPressed: () => _openQRScanner(user.uid, _cachedProviderName),
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
          ),
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
      body: FutureBuilder<ProviderProfile?>(
        future: _auth.getProviderProfile(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
          }
          final profile = snapshot.data;
          final rawName = profile?.displayName.isNotEmpty == true
              ? profile!.displayName
              : (user.displayName ?? 'Vet / Clinic Provider');
          final formattedName = _formatProviderName(rawName);
          _cachedProviderName = formattedName;

          return IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(user.uid, user.email ?? '', formattedName, profile),
              _buildAppointmentsTab(user.uid, formattedName),
              _buildServicesTab(user.uid, formattedName),
              _buildCommunityTab(user.uid, formattedName),
              _buildProfileTab(profile, formattedName, user.email ?? '', user.uid),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppTheme.primaryTeal,
        unselectedItemColor: AppTheme.textSecondary,
        backgroundColor: AppTheme.surface,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _pendingAppointmentsCount > 0,
              backgroundColor: _hasPendingEmergency ? Colors.red.shade700 : const Color(0xFFE5A038),
              label: Text(
                '$_pendingAppointmentsCount',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              child: const Icon(Icons.calendar_today_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _pendingAppointmentsCount > 0,
              backgroundColor: _hasPendingEmergency ? Colors.red.shade700 : const Color(0xFFE5A038),
              label: Text(
                '$_pendingAppointmentsCount',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              child: const Icon(Icons.calendar_today),
            ),
            label: 'Appointments',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.medical_services_outlined),
            activeIcon: Icon(Icons.medical_services),
            label: 'Services',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            activeIcon: Icon(Icons.campaign),
            label: 'Community',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ==========================================
  // EMAIL VERIFICATION BANNER
  // ==========================================
  Widget _buildEmailVerificationBanner(String email) {
    if (_auth.isEmailVerified()) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: Color(0xFFE65100), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Email verification pending',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE65100)),
                ),
                Text(
                  'Verify $email to ensure patient notifications work properly.',
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

  // ==========================================
  // TAB 0: HOME / OVERVIEW
  // ==========================================
  Widget _buildHomeTab(String providerId, String email, String displayName, ProviderProfile? profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEmailVerificationBanner(email),

          // Provider Header Card with Teal Gradient
          FadeInSlide(
            direction: AxisDirection.down,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppTheme.tealHeaderGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: AppTheme.softShadow,
              ),
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.local_hospital_outlined, size: 32, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'VET & CLINIC PORTAL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            if (profile != null) ...[
                              const SizedBox(width: 8),
                              OpenStatusPill(provider: profile, compact: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          displayName,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        Text(
                          email,
                          style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Aggregated Live Streams for Bento Stats & Today's Schedule
          StreamBuilder<List<Reservation>>(
            stream: _auth.getVetReservations(providerId),
            builder: (context, resSnap) {
              return StreamBuilder<List<Booking>>(
                stream: _auth.getClinicBookings(providerId),
                builder: (context, bookSnap) {
                  return StreamBuilder<List<ServiceOffering>>(
                    stream: _auth.getClinicServices(providerId),
                    builder: (context, srvSnap) {
                      final reservations = resSnap.data ?? [];
                      final bookings = bookSnap.data ?? [];
                      final services = srvSnap.data ?? [];

                      final now = DateTime.now();

                      // Pending counts
                      final pendingRes = reservations.where((r) => r.status == RequestStatus.pending).length;
                      final pendingBook = bookings.where((b) => b.status == RequestStatus.pending).length;
                      final totalPending = pendingRes + pendingBook;

                      // Accepted counts
                      final acceptedRes = reservations.where((r) => r.status == RequestStatus.accepted).length;
                      final acceptedBook = bookings.where((b) => b.status == RequestStatus.accepted).length;
                      final totalAccepted = acceptedRes + acceptedBook;

                      // Total requests
                      final totalRequests = reservations.length + bookings.length;
                      final activeServicesCount = services.where((s) => s.active).length;

                      // Today's schedule items
                      final todayRes = reservations.where((r) =>
                          r.status == RequestStatus.accepted &&
                          r.requestedAt.year == now.year &&
                          r.requestedAt.month == now.month &&
                          r.requestedAt.day == now.day).toList();

                      final todayBook = bookings.where((b) =>
                          b.status == RequestStatus.accepted &&
                          b.scheduledAt.year == now.year &&
                          b.scheduledAt.month == now.month &&
                          b.scheduledAt.day == now.day).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bento Metric Cards
                          Row(
                            children: [
                              _buildStatBox('Pending', totalPending.toString(), Icons.pending_actions, const Color(0xFFE5A038)),
                              const SizedBox(width: 10),
                              _buildStatBox('Accepted', totalAccepted.toString(), Icons.event_available, AppTheme.primaryTeal),
                              const SizedBox(width: 10),
                              _buildStatBox('Services', activeServicesCount.toString(), Icons.medical_services_outlined, AppTheme.terracotta),
                              const SizedBox(width: 10),
                              _buildStatBox('Total', totalRequests.toString(), Icons.list_alt, AppTheme.vetAccent),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Automated Clinic Operations & Live Queue Command Center
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.35), width: 1.5),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryTealLight,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.bolt_rounded, color: AppTheme.primaryTealDark, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Automated Clinic Command Center',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                                          ),
                                          Text(
                                            'Auto-Accept Queue • QR Check-In • 1-Tap Smart EMR',
                                            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 18),
                                Row(
                                  children: [
                                    const Icon(Icons.auto_mode_rounded, size: 18, color: AppTheme.primaryTeal),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Auto-Accept Conflict-Free Bookings',
                                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                          ),
                                          Text(
                                            'Automatically accepts valid slots & assigns Queue Numbers (Q-01)',
                                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _autoAcceptEnabled,
                                      activeThumbColor: AppTheme.primaryTeal,
                                      onChanged: (val) {
                                        setState(() => _autoAcceptEnabled = val);
                                        if (val) {
                                          _triggerAutoProcessPendingQueue(providerId, displayName);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _openQRScanner(providerId, displayName),
                                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 17, color: Colors.white),
                                        label: const Text(
                                          'Scan QR Check-In',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryTeal,
                                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _callNextPatientAndOpenEMR(displayName),
                                        icon: const Icon(Icons.medical_services_rounded, size: 17, color: Colors.white),
                                        label: const Text(
                                          'Call Next & EMR',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.terracotta,
                                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (totalPending > 0) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _isAutoProcessingQueue
                                          ? null
                                          : () => _triggerAutoProcessPendingQueue(providerId, displayName),
                                      icon: const Icon(Icons.playlist_add_check_circle_outlined, size: 17),
                                      label: Text(
                                        '⚡ Auto-Process All $totalPending Pending Queue Request(s) Now',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.primaryTealDark,
                                        side: const BorderSide(color: AppTheme.primaryTeal),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),

                          // Today's Schedule
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Today's Live Patient Queue",
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              Text(
                                '${todayRes.length + todayBook.length} appointments',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (todayRes.isEmpty && todayBook.isEmpty)
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
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                ),
                              ),
                            )
                          else ...[
                            ...todayRes.map((r) => FadeInSlide(
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
                                        leading: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryTealLight,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.pets, color: AppTheme.primaryTeal, size: 20),
                                        ),
                                        title: Text(
                                          '${r.queueNumber != null ? '[${r.queueNumber}] ' : ''}🐾 ${r.catName} (${r.visitType})',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                        subtitle: Text(
                                          'Owner: ${r.ownerName} • ${DateFormat('hh:mm a').format(r.requestedAt)}${r.checkedInAt != null ? ' • 🟢 Checked-In' : ''}',
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                                        ),
                                        trailing: TextButton.icon(
                                          onPressed: () => _showCompleteReservationDialog(r, providerName: displayName),
                                          icon: const Icon(Icons.medical_services_outlined, size: 15, color: AppTheme.primaryTealDark),
                                          label: const Text('Start EMR', style: TextStyle(color: AppTheme.primaryTealDark, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                            ...todayBook.map((b) => FadeInSlide(
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
                                        leading: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: AppTheme.terracottaLight,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.bookmark, color: AppTheme.terracotta, size: 20),
                                        ),
                                        title: Text(
                                          '${b.queueNumber != null ? '[${b.queueNumber}] ' : ''}💉 ${b.catName} • ${b.serviceName}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                        subtitle: Text(
                                          'Owner: ${b.ownerName} • ${DateFormat('hh:mm a').format(b.scheduledAt)}${b.checkedInAt != null ? ' • 🟢 Checked-In' : ''}',
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                                        ),
                                        trailing: TextButton.icon(
                                          onPressed: () => _showCompleteBookingDialog(b, providerName: displayName),
                                          icon: const Icon(Icons.medical_services_outlined, size: 15, color: AppTheme.terracotta),
                                          label: const Text('Start EMR', style: TextStyle(color: AppTheme.terracotta, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 22),

          // Provider Info Card
          const Text('Clinic & Practice Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _infoRow(Icons.location_city, 'City', profile?.city.isNotEmpty == true ? profile!.city : 'Not specified'),
                const Divider(),
                _infoRow(Icons.home, 'Address', profile?.address.isNotEmpty == true ? profile!.address : 'Not specified'),
                const Divider(),
                _infoRow(Icons.phone, 'Phone', profile?.phone.isNotEmpty == true ? profile!.phone : 'Not specified'),
                const Divider(),
                _infoRow(Icons.schedule, 'Hours', profile?.hoursLabel.isNotEmpty == true ? profile!.hoursLabel : 'Mon-Sat • 8:00 AM - 6:00 PM'),
                if (profile?.specialty?.isNotEmpty == true) ...[
                  const Divider(),
                  _infoRow(Icons.star, 'Specialty', profile!.specialty!),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => MapUtils.openDirections(
                      destinationAddress: '${profile?.address ?? ''}, ${profile?.city ?? 'Metro Manila'}',
                      clinicName: displayName,
                      context: context,
                    ),
                    icon: const Icon(Icons.map_outlined, size: 17, color: AppTheme.primaryTealDark),
                    label: const Text(
                      '📍 Verify / Open Clinic Pin in Google Maps',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryTealDark),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Visit Types
          if (profile?.visitTypes.isNotEmpty == true) ...[
            const Text('Consultation Types Handled', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile!.visitTypes.map((type) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTealLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: AppTheme.primaryTeal),
                      const SizedBox(width: 5),
                      Text(
                        type,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTealDark),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, Color color) {
    final intVal = int.tryParse(value) ?? 0;
    return Expanded(
      child: BouncingScale(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              AnimatedCounterText(
                value: intVal,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: APPOINTMENTS INBOX (UNIFIED)
  // ==========================================
  Widget _buildAppointmentsTab(String providerId, String providerName) {
    return Column(
      children: [
        // Type filter pills (All vs Consultations vs Service Bookings)
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _buildTypeFilterChip('all', 'All'),
              const SizedBox(width: 8),
              _buildTypeFilterChip('reservations', 'Consultations'),
              const SizedBox(width: 8),
              _buildTypeFilterChip('bookings', 'Services'),
            ],
          ),
        ),

        // Status filter chips + Automated Queue Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            children: [
              Row(
                children: [
                  FilterChip(
                    selected: _appointmentStatusFilter == 'pending',
                    label: const Text('Pending'),
                    selectedColor: const Color(0xFFFDEFD7),
                    checkmarkColor: const Color(0xFFC77700),
                    labelStyle: TextStyle(
                      color: _appointmentStatusFilter == 'pending' ? const Color(0xFF8A5200) : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    onSelected: (val) => setState(() => _appointmentStatusFilter = 'pending'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _appointmentStatusFilter == 'accepted',
                    label: const Text('Accepted / Queue'),
                    selectedColor: AppTheme.primaryTealLight,
                    checkmarkColor: AppTheme.primaryTeal,
                    labelStyle: TextStyle(
                      color: _appointmentStatusFilter == 'accepted' ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    onSelected: (val) => setState(() => _appointmentStatusFilter = 'accepted'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _appointmentStatusFilter == 'history',
                    label: const Text('History'),
                    selectedColor: const Color(0xFFEDE7F6),
                    checkmarkColor: const Color(0xFF673AB7),
                    labelStyle: TextStyle(
                      color: _appointmentStatusFilter == 'history' ? const Color(0xFF512DA8) : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    onSelected: (val) => setState(() => _appointmentStatusFilter = 'history'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openQRScanner(providerId, providerName),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 15),
                      label: const Text('QR Check-In', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryTealDark,
                        side: const BorderSide(color: AppTheme.primaryTeal),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _triggerAutoProcessPendingQueue(providerId, providerName),
                      icon: const Icon(Icons.auto_mode_rounded, size: 15),
                      label: const Text('Auto-Queue All', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryTealDark,
                        side: const BorderSide(color: AppTheme.primaryTeal),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _callNextPatientAndOpenEMR(providerName),
                      icon: const Icon(Icons.medical_services_rounded, size: 15, color: Colors.white),
                      label: const Text('Call Next', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.terracotta,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // List builder combining both streams
        Expanded(
          child: StreamBuilder<List<Reservation>>(
            stream: _auth.getVetReservations(providerId),
            builder: (context, resSnap) {
              return StreamBuilder<List<Booking>>(
                stream: _auth.getClinicBookings(providerId),
                builder: (context, bookSnap) {
                  if (resSnap.hasError || bookSnap.hasError) {
                    return Center(child: Text('Error loading requests: ${resSnap.error ?? bookSnap.error}'));
                  }
                  if (!resSnap.hasData || !bookSnap.hasData) {
                    return const SkeletonCardList(itemCount: 3);
                  }

                  final allRes = resSnap.data!;
                  final allBook = bookSnap.data!;
                  final now = DateTime.now();

                  // Convert both to a unified item list with DateTime for unified sorting
                  final List<_UnifiedAppointmentItem> items = [];

                  if (_appointmentTypeFilter == 'all' || _appointmentTypeFilter == 'reservations') {
                    for (final r in allRes) {
                      final isEmergency = r.visitType.toLowerCase().contains('emergency');
                      final eff = effectiveStatus(
                        stored: r.status,
                        start: isEmergency
                            ? r.requestedAt.add(const Duration(hours: 12))
                            : r.requestedAt,
                        end: r.requestedAt.add(const Duration(hours: 1)),
                        now: now,
                      );
                      if (_matchesStatus(eff, _appointmentStatusFilter)) {
                        items.add(_UnifiedAppointmentItem.fromReservation(r, eff));
                      }
                    }
                  }

                  if (_appointmentTypeFilter == 'all' || _appointmentTypeFilter == 'bookings') {
                    for (final b in allBook) {
                      final eff = effectiveStatus(
                        stored: b.status,
                        start: b.scheduledAt,
                        end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
                        now: now,
                      );
                      if (_matchesStatus(eff, _appointmentStatusFilter)) {
                        items.add(_UnifiedAppointmentItem.fromBooking(b, eff));
                      }
                    }
                  }

                  // Pin pending Emergency requests to the very top above standard consultations/services
                  items.sort((a, b) {
                    final aUrgent = a.isEmergency && a.effectiveStatus == RequestStatus.pending;
                    final bUrgent = b.isEmergency && b.effectiveStatus == RequestStatus.pending;
                    if (aUrgent != bUrgent) {
                      return aUrgent ? -1 : 1;
                    }
                    if (a.isEmergency != b.isEmergency) {
                      return a.isEmergency ? -1 : 1;
                    }
                    return b.dateTime.compareTo(a.dateTime);
                  });

                  if (items.isEmpty) {
                    return BouncyPawEmptyState(
                      title: 'No $_appointmentStatusFilter appointments',
                      subtitle: 'Incoming pet owner consultations and service bookings will appear here.',
                      badgeIcon: Icons.inbox_outlined,
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return FadeInSlide(
                        delay: Duration(milliseconds: 30 * index),
                        child: BouncingScale(
                          child: item.isReservation
                              ? _buildReservationCard(item.reservation!, item.effectiveStatus)
                              : _buildBookingCard(item.booking!, item.effectiveStatus),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilterChip(String value, String label) {
    final isSelected = _appointmentTypeFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _appointmentTypeFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? AppTheme.primaryTeal : AppTheme.borderLight),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  bool _matchesStatus(RequestStatus status, String filter) {
    if (filter == 'pending') return status == RequestStatus.pending;
    if (filter == 'accepted') return status == RequestStatus.accepted;
    return status == RequestStatus.declined ||
        status == RequestStatus.completed ||
        status == RequestStatus.cancelled ||
        status == RequestStatus.expired;
  }

  Widget _buildReservationCard(Reservation res, RequestStatus effStatus) {
    final isEmergency = res.visitType.toLowerCase().contains('emergency');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isEmergency ? const Color(0xFFFFFAFA) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergency ? Colors.red.shade600 : AppTheme.borderLight,
          width: isEmergency ? 2.0 : 1.0,
        ),
        boxShadow: isEmergency
            ? [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEmergency && effStatus == RequestStatus.pending) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.priority_high_rounded, color: Colors.white, size: 15),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '🚨 PRIORITY EMERGENCY TRIAGE — PINNED TO TOP',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isEmergency
                            ? const Color(0xFFFFEBEE)
                            : AppTheme.primaryTealLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isEmergency ? 'EMERGENCY' : 'CONSULTATION',
                        style: TextStyle(
                          color: isEmergency
                              ? Colors.red.shade800
                              : AppTheme.primaryTealDark,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (res.queueNumber != null && res.queueNumber!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTealDark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          res.queueNumber!,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        res.catName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (res.checkedInAt != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.statusSafe.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '🟢 CHECKED-IN',
                          style: TextStyle(color: AppTheme.statusSafe, fontSize: 9.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              effStatus.buildBadge(),
            ],
          ),
          AppointmentStatusStepper(status: effStatus),
          const SizedBox(height: 8),
          Text('Visit Type: ${res.visitType}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('Owner: ${res.ownerName}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(
            'Requested: ${DateFormat('EEE, MMM d, yyyy • hh:mm a').format(res.requestedAt)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
          ),
          if (res.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isEmergency
                    ? const Color(0xFFFFEBEE)
                    : AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isEmergency
                      ? Colors.red.shade200
                      : AppTheme.borderLight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isEmergency
                            ? Icons.emergency_outlined
                            : Icons.description_outlined,
                        size: 14,
                        color: isEmergency
                            ? Colors.red.shade800
                            : AppTheme.primaryTealDark,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isEmergency
                            ? 'Emergency Symptoms & Urgency Details:'
                            : 'Owner Notes / Symptoms:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isEmergency
                              ? Colors.red.shade800
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    res.notes,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isEmergency
                          ? Colors.red.shade900
                          : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (res.providerNote != null && res.providerNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFBE9E7), borderRadius: BorderRadius.circular(8)),
              child: Text('Clinic Note: ${res.providerNote}', style: const TextStyle(fontSize: 12, color: Color(0xFFD84315))),
            ),
          ],
          if (effStatus == RequestStatus.pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleAcceptReservation(res),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEmergency ? Colors.red.shade700 : AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      isEmergency ? 'Accept Emergency Triage' : 'Accept & Queue',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showDeclineReservationDialog(res.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
          if (effStatus == RequestStatus.accepted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (res.checkedInAt == null) ...[
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _auth.checkInPatientWithQR(
                            catId: res.catId,
                            providerId: res.vetId,
                            providerName: _cachedProviderName,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('🟢 ${res.catName} checked-in at reception & assigned priority queue!'),
                                backgroundColor: AppTheme.primaryTeal,
                              ),
                            );
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                      label: const Text('Check-In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryTealDark,
                        side: const BorderSide(color: AppTheme.primaryTeal),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _showCompleteReservationDialog(res),
                    icon: const Icon(Icons.medical_services_rounded, size: 17),
                    label: const Text('Open Smart EMR & Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingCard(Booking b, RequestStatus effStatus) {
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.terracottaLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'SERVICE',
                        style: TextStyle(color: AppTheme.terracotta, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (b.queueNumber != null && b.queueNumber!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTealDark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          b.queueNumber!,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        b.catName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (b.checkedInAt != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.statusSafe.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '🟢 CHECKED-IN',
                          style: TextStyle(color: AppTheme.statusSafe, fontSize: 9.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              effStatus.buildBadge(),
            ],
          ),
          AppointmentStatusStepper(status: effStatus),
          const SizedBox(height: 8),
          Text('Service: ${b.serviceName} (₱${b.servicePrice.toStringAsFixed(0)})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('Owner: ${b.ownerName}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(
            'Scheduled: ${DateFormat('EEE, MMM d, yyyy • hh:mm a').format(b.scheduledAt)} (${b.serviceDurationMinutes} mins)',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
          ),
          if (b.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.description_outlined, size: 14, color: AppTheme.primaryTealDark),
                      SizedBox(width: 5),
                      Text(
                        'Owner Request Details / Symptoms:',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(b.notes, style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary)),
                ],
              ),
            ),
          ],
          if (b.providerNote != null && b.providerNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFBE9E7), borderRadius: BorderRadius.circular(8)),
              child: Text('Clinic Note: ${b.providerNote}', style: const TextStyle(fontSize: 12, color: Color(0xFFD84315))),
            ),
          ],
          if (effStatus == RequestStatus.pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleAcceptBooking(b),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Accept & Queue', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showDeclineBookingDialog(b.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
          if (effStatus == RequestStatus.accepted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (b.checkedInAt == null) ...[
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _auth.checkInPatientWithQR(
                            catId: b.catId,
                            providerId: b.clinicId,
                            providerName: _cachedProviderName,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('🟢 ${b.catName} checked-in at reception & assigned priority queue!'),
                                backgroundColor: AppTheme.primaryTeal,
                              ),
                            );
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                      label: const Text('Check-In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryTealDark,
                        side: const BorderSide(color: AppTheme.primaryTeal),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _showCompleteBookingDialog(b),
                    icon: const Icon(Icons.medical_services_rounded, size: 17),
                    label: const Text('Open Smart EMR & Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleAcceptReservation(Reservation res) async {
    final user = _auth.getCurrentUser();
    if (user != null) {
      final isOccupied = await _auth.isProviderSlotOccupied(
        user.uid,
        res.requestedAt,
        30,
        excludeId: res.id,
      );
      if (isOccupied && mounted) {
        final timeStr = DateFormat('hh:mm a').format(res.requestedAt);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Time Slot Conflict'),
              ],
            ),
            content: Text(
              'You already have an accepted appointment that overlaps with this time ($timeStr).\n\nDo you want to double-book this slot anyway?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Accept Anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }
    await _updateReservationStatus(res.id, RequestStatus.accepted);
  }

  Future<void> _handleAcceptBooking(Booking b) async {
    final user = _auth.getCurrentUser();
    if (user != null) {
      final isOccupied = await _auth.isProviderSlotOccupied(
        user.uid,
        b.scheduledAt,
        b.serviceDurationMinutes,
        excludeId: b.id,
      );
      if (isOccupied && mounted) {
        final timeStr = DateFormat('hh:mm a').format(b.scheduledAt);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Time Slot Conflict'),
              ],
            ),
            content: Text(
              'You already have an accepted appointment that overlaps with this time ($timeStr • ${b.serviceDurationMinutes} mins).\n\nDo you want to double-book this slot anyway?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Accept Anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }
    await _updateBookingStatus(b.id, RequestStatus.accepted);
  }

  void _showCompleteReservationDialog(Reservation res, {String? providerName}) {
    showDialog(
      context: context,
      builder: (_) => ClinicalEMRDialog(
        appointmentId: res.id,
        isBooking: false,
        catId: res.catId,
        catName: res.catName,
        ownerId: res.ownerId,
        ownerName: res.ownerName,
        catBreed: res.catBreed,
        clinicName: providerName ?? (res.vetName.isNotEmpty ? res.vetName : _cachedProviderName),
        baseServiceFeePhp: 550.0,
        initialVisitNotes: res.notes,
      ),
    );
  }

  void _showCompleteBookingDialog(Booking b, {String? providerName}) {
    showDialog(
      context: context,
      builder: (_) => ClinicalEMRDialog(
        appointmentId: b.id,
        isBooking: true,
        catId: b.catId,
        catName: b.catName,
        ownerId: b.ownerId,
        ownerName: b.ownerName,
        catBreed: b.catBreed,
        clinicName: providerName ?? (b.clinicName.isNotEmpty ? b.clinicName : _cachedProviderName),
        baseServiceFeePhp: b.servicePrice > 0 ? b.servicePrice : 550.0,
        initialVisitNotes: b.notes,
      ),
    );
  }

  Future<void> _updateReservationStatus(String id, RequestStatus status, {String? note}) async {
    try {
      await _auth.respondToReservation(id, status, providerNote: note);
      if (mounted) {
        if (status == RequestStatus.accepted) {
          await showPurrSyncSuccessOverlay(
            context,
            title: 'Reservation Accepted!',
            subtitle: 'The pet owner has been notified.',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reservation updated to ${status.label}!'), backgroundColor: AppTheme.primaryTeal),
          );
        }
      }
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _updateBookingStatus(String id, RequestStatus status, {String? note}) async {
    try {
      await _auth.respondToBooking(id, status, providerNote: note);
      if (mounted) {
        if (status == RequestStatus.accepted) {
          await showPurrSyncSuccessOverlay(
            context,
            title: 'Booking Accepted!',
            subtitle: 'The pet owner has been notified.',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Booking updated to ${status.label}!'), backgroundColor: AppTheme.primaryTeal),
          );
        }
      }
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  void _showDeclineReservationDialog(String id) {
    final noteController = TextEditingController();
    String? declineError;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Decline Reservation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reason or note for the cat owner (required):', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'e.g., Doctor is fully booked at this hour, emergency surgery, etc.',
                  border: const OutlineInputBorder(),
                  errorText: declineError,
                ),
                onChanged: (_) {
                  if (declineError != null) {
                    setDialogState(() => declineError = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Back')),
            ElevatedButton(
              onPressed: () {
                final note = noteController.text.trim();
                if (note.isEmpty) {
                  setDialogState(() => declineError = 'A reason is required so the pet owner is informed.');
                  return;
                }
                Navigator.pop(dialogCtx);
                _updateReservationStatus(id, RequestStatus.declined, note: note);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeclineBookingDialog(String id) {
    final noteController = TextEditingController();
    String? declineError;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Decline Booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reason or note for the cat owner (required):', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'e.g., Equipment under maintenance, clinic closed unexpectedly, etc.',
                  border: const OutlineInputBorder(),
                  errorText: declineError,
                ),
                onChanged: (_) {
                  if (declineError != null) {
                    setDialogState(() => declineError = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Back')),
            ElevatedButton(
              onPressed: () {
                final note = noteController.text.trim();
                if (note.isEmpty) {
                  setDialogState(() => declineError = 'A reason is required so the pet owner is informed.');
                  return;
                }
                Navigator.pop(dialogCtx);
                _updateBookingStatus(id, RequestStatus.declined, note: note);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: SERVICES CATALOG (CRUD)
  // ==========================================
  Widget _buildServicesTab(String providerId, String providerName) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<ServiceOffering>>(
        stream: _auth.getClinicServices(providerId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error loading services: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));

          final services = snapshot.data!;
          if (services.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.medical_services_outlined, size: 72, color: AppTheme.textTertiary),
                    const SizedBox(height: 16),
                    const Text('No services in your catalog', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Auto-populate standard feline veterinary services in 1 tap or add a custom service.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _handleAutoSeedServices(providerId, providerName),
                      icon: const Icon(Icons.bolt_rounded, color: Colors.white),
                      label: const Text('⚡ 1-Tap Auto-Load Feline Clinic Catalog', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _openServiceDialog(providerId, providerName),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Custom Service'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryTealDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleAutoSeedServices(providerId, providerName),
                    icon: const Icon(Icons.bolt_rounded, size: 17, color: AppTheme.primaryTealDark),
                    label: const Text(
                      '⚡ 1-Tap Auto-Load Standard Feline Services Catalog',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppTheme.primaryTealDark),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: services.length,
                  itemBuilder: (context, index) {
                    final s = services[index];
                    return FadeInSlide(
                      delay: Duration(milliseconds: 30 * index),
                      child: BouncingScale(
                        child: Container(
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryTealLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      s.category.toUpperCase(),
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18, color: AppTheme.textSecondary),
                                    onPressed: () => _openServiceDialog(providerId, providerName, existing: s),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                    onPressed: () => _confirmDeleteService(s.id),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              if (s.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(s.description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${s.durationMinutes} mins', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                                  Text('₱${s.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openServiceDialog(providerId, providerName),
        backgroundColor: AppTheme.primaryTeal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Future<void> _handleAutoSeedServices(String providerId, String providerName) async {
    try {
      final count = await _auth.autoSeedStandardClinicServices(
        providerId: providerId,
        providerName: providerName,
      );
      if (!mounted) return;
      if (count > 0) {
        await showPurrSyncSuccessOverlay(
          context,
          title: 'Loaded $count Feline Services!',
          subtitle: 'Standard veterinary catalog & PHP pricing added automatically.',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All standard feline veterinary services are already in your catalog!'),
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
  }

  void _openServiceDialog(String providerId, String providerName, {ServiceOffering? existing}) {
    const standardCategories = ['Consultation', 'Vaccination', 'Grooming', 'Surgery', 'Dental', 'Emergency', 'Other'];
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.toStringAsFixed(2) : '');
    final durationCtrl = TextEditingController(text: existing != null ? existing.durationMinutes.toString() : '30');

    String initialCat = existing?.category ?? 'Consultation';
    String initialCustomCat = '';
    if (existing != null && !standardCategories.contains(existing.category)) {
      initialCat = 'Other';
      initialCustomCat = existing.category.startsWith('Other: ')
          ? existing.category.substring('Other: '.length)
          : existing.category;
    }
    String category = initialCat;
    final customCategoryCtrl = TextEditingController(text: initialCustomCat);
    String? customCategoryError;
    bool active = existing?.active ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'Add Service' : 'Edit Service', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Service Name *', prefixIcon: Icon(Icons.medical_services))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: standardCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setSheetState(() {
                    category = val ?? 'Consultation';
                    customCategoryError = null;
                  }),
                ),
                if (category == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customCategoryCtrl,
                    decoration: InputDecoration(
                      labelText: 'Specify Custom Details / Name *',
                      hintText: 'e.g., Ultrasound Imaging, Microchipping',
                      prefixIcon: const Icon(Icons.edit_note, color: AppTheme.primaryTeal),
                      errorText: customCategoryError,
                    ),
                    onChanged: (_) {
                      if (customCategoryError != null) {
                        setSheetState(() => customCategoryError = null);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Price (\$) *', prefixIcon: Icon(Icons.attach_money)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: durationCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Duration (mins) *', prefixIcon: Icon(Icons.timer)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active and available for booking'),
                  value: active,
                  activeThumbColor: AppTheme.primaryTeal,
                  onChanged: (val) => setSheetState(() => active = val),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                      final duration = int.tryParse(durationCtrl.text.trim()) ?? 30;
                      if (name.isEmpty) return;

                      String finalCategory = category;
                      if (category == 'Other') {
                        final customCat = customCategoryCtrl.text.trim();
                        if (customCat.isEmpty) {
                          setSheetState(() => customCategoryError = 'Please specify the custom service category / details.');
                          return;
                        }
                        finalCategory = 'Other: $customCat';
                      }

                      final service = ServiceOffering(
                        id: existing?.id ?? '',
                        providerId: providerId,
                        providerName: providerName,
                        name: name,
                        description: descCtrl.text.trim(),
                        category: finalCategory,
                        price: price,
                        durationMinutes: duration,
                        active: active,
                        createdAt: existing?.createdAt ?? DateTime.now(),
                        updatedAt: DateTime.now(),
                      );

                      try {
                        if (existing == null) {
                          await _auth.addService(service);
                        } else {
                          await _auth.updateService(service);
                        }
                        if (context.mounted) {
                          Navigator.pop(sheetCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(existing == null ? 'Service added!' : 'Service updated!'), backgroundColor: AppTheme.primaryTeal),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(existing == null ? 'Create Service' : 'Save Changes', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteService(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service?'),
        content: const Text('Are you sure you want to remove this service from your catalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _auth.deleteService(id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: COMMUNITY / ANNOUNCEMENTS (CRUD)
  // ==========================================
  Widget _buildCommunityTab(String providerId, String providerName) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<Announcement>>(
        stream: _auth.getMyAnnouncements(providerId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error loading posts: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));

          final announcements = snapshot.data!;
          if (announcements.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.campaign_outlined, size: 72, color: AppTheme.textTertiary),
                  const SizedBox(height: 16),
                  const Text('No community posts yet', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Share health alerts, vaccination drives, and pet care events.', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _openAnnouncementDialog(providerId, providerName),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Create Announcement', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                delay: Duration(milliseconds: 30 * index),
                child: BouncingScale(
                  child: Container(
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: item.type == 'event' ? const Color(0xFFEDE7F6) : AppTheme.primaryTealLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.type.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: item.type == 'event' ? const Color(0xFF673AB7) : AppTheme.primaryTealDark,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () => _confirmDeleteAnnouncement(item.id),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(item.body, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                        if (item.eventDate != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.event, size: 14, color: AppTheme.primaryTeal),
                              const SizedBox(width: 6),
                              Text('Date: ${DateFormat('yyyy-MM-dd • hh:mm a').format(item.eventDate!)}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                        if (item.location != null && item.location!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.place, size: 14, color: AppTheme.primaryTeal),
                              const SizedBox(width: 6),
                              Text('Location: ${item.location}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAnnouncementDialog(providerId, providerName),
        backgroundColor: AppTheme.primaryTeal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _openAnnouncementDialog(String providerId, String providerName) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final detailTagCtrl = TextEditingController();
    String type = 'general';
    String? customDetailError;
    DateTime? eventDate;
    DateTime? expiresAt;
    bool isClosedAllDay = false;
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 12, minute: 0);

    void syncFormattedScheduleNote(BuildContext ctx) {
      final baseDate = eventDate ?? DateTime.now();
      final datePart = DateFormat('MMM d, yyyy').format(baseDate);
      if (type == 'schedule' && isClosedAllDay) {
        detailTagCtrl.text = '$datePart • Closed All Day';
      } else {
        final startStr = startTime.format(ctx);
        final endStr = endTime.format(ctx);
        detailTagCtrl.text = '$datePart • $startStr - $endStr';
      }
      eventDate = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        (type == 'schedule' && isClosedAllDay) ? 0 : startTime.hour,
        (type == 'schedule' && isClosedAllDay) ? 0 : startTime.minute,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Announcement / Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title *')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Post Type'),
                  items: const [
                    DropdownMenuItem(value: 'drive', child: Text('Free Kapon / Deworming / Vaccination Drive')),
                    DropdownMenuItem(value: 'schedule', child: Text('Schedule / Hours Update')),
                    DropdownMenuItem(value: 'service_update', child: Text('Service Update')),
                    DropdownMenuItem(value: 'payment_facility', child: Text('Payment & Facility Update')),
                    DropdownMenuItem(value: 'general', child: Text('General Health Update')),
                    DropdownMenuItem(value: 'others', child: Text('Others (Custom Notice)')),
                  ],
                  onChanged: (val) => setSheetState(() {
                    type = val ?? 'general';
                    customDetailError = null;
                    if (type == 'schedule' || type == 'drive') {
                      eventDate ??= DateTime.now().add(const Duration(days: 1));
                      syncFormattedScheduleNote(context);
                    }
                  }),
                ),
                if (type == 'schedule' || type == 'drive') ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTealLight.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.event_available, size: 17, color: AppTheme.primaryTealDark),
                            const SizedBox(width: 6),
                            Text(
                              type == 'schedule'
                                  ? 'Interactive Date & Hours Selector'
                                  : 'Interactive Event Date & Time Selector',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryTealDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 1. Date Picker Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: eventDate ?? DateTime.now().add(const Duration(days: 1)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null && context.mounted) {
                                setSheetState(() {
                                  eventDate = picked;
                                  syncFormattedScheduleNote(context);
                                });
                              }
                            },
                            icon: const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.primaryTealDark),
                            label: Text(
                              eventDate == null
                                  ? 'Select Event / Schedule Date'
                                  : 'Date: ${DateFormat('EEE, MMM d, yyyy').format(eventDate!)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryTealDark),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppTheme.surface,
                              side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.45)),
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        // 2. Closed All Day vs Adjusted Hours toggle for Schedule / Hours Update
                        if (type == 'schedule') ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const SizedBox(
                                    width: double.infinity,
                                    child: Text('Adjusted Hours', textAlign: TextAlign.center),
                                  ),
                                  selected: !isClosedAllDay,
                                  selectedColor: AppTheme.primaryTeal,
                                  backgroundColor: AppTheme.surface,
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: !isClosedAllDay ? Colors.white : AppTheme.textPrimary,
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setSheetState(() {
                                        isClosedAllDay = false;
                                        syncFormattedScheduleNote(context);
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const SizedBox(
                                    width: double.infinity,
                                    child: Text('Closed All Day', textAlign: TextAlign.center),
                                  ),
                                  selected: isClosedAllDay,
                                  selectedColor: Colors.red.shade700,
                                  backgroundColor: AppTheme.surface,
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isClosedAllDay ? Colors.white : AppTheme.textPrimary,
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setSheetState(() {
                                        isClosedAllDay = true;
                                        syncFormattedScheduleNote(context);
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                        // 3. Start / Open Time & End / Close Time Clock Pickers
                        if (type == 'drive' || !isClosedAllDay) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: startTime,
                                    );
                                    if (picked != null && context.mounted) {
                                      setSheetState(() {
                                        startTime = picked;
                                        syncFormattedScheduleNote(context);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.access_time, size: 16, color: AppTheme.primaryTealDark),
                                  label: Text(
                                    'Start: ${startTime.format(context)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryTealDark,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: AppTheme.surface,
                                    side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.45)),
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: endTime,
                                    );
                                    if (picked != null && context.mounted) {
                                      setSheetState(() {
                                        endTime = picked;
                                        syncFormattedScheduleNote(context);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.schedule_outlined, size: 16, color: AppTheme.primaryTealDark),
                                  label: Text(
                                    'End: ${endTime.format(context)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryTealDark,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: AppTheme.surface,
                                    side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.45)),
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (type == 'others' || type == 'schedule' || type == 'drive') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailTagCtrl,
                    decoration: InputDecoration(
                      labelText: type == 'others'
                          ? 'Specify Custom Details / Name *'
                          : 'Hours / Holiday Note (Auto-filled & Editable)',
                      hintText: type == 'others'
                          ? 'e.g., Emergency Clinic Closure Notice'
                          : 'e.g., Oct 24, 2026 • 8:00 AM - 12:00 PM',
                      prefixIcon: const Icon(Icons.edit_note, color: AppTheme.primaryTeal),
                      errorText: customDetailError,
                    ),
                    onChanged: (_) {
                      if (customDetailError != null) {
                        setSheetState(() => customDetailError = null);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(controller: bodyCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Body / Details *')),
                if (type == 'drive' || type == 'event') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      prefixIcon: Icon(Icons.place_outlined, color: AppTheme.primaryTeal),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(expiresAt == null ? 'Visible Until (optional)' : 'Expires: ${DateFormat('yyyy-MM-dd').format(expiresAt!)}'),
                  trailing: const Icon(Icons.timer_off_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => expiresAt = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      var body = bodyCtrl.text.trim();
                      final tag = detailTagCtrl.text.trim();

                      if (type == 'others' && tag.isEmpty) {
                        setSheetState(() => customDetailError = 'Please specify the custom notice details / name.');
                        return;
                      }
                      if (title.isEmpty || body.isEmpty) return;

                      if (tag.isNotEmpty) {
                        body = '[$tag]\n$body';
                      }

                      final ann = Announcement(
                        id: '',
                        title: title,
                        body: body,
                        type: type,
                        authorId: providerId,
                        authorName: providerName,
                        authorRole: 'provider',
                        eventDate: eventDate,
                        location: locCtrl.text.trim(),
                        published: true,
                        expiresAt: expiresAt,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      );

                      try {
                        await _auth.createAnnouncement(ann);
                        if (context.mounted) {
                          Navigator.pop(sheetCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Announcement published!'), backgroundColor: AppTheme.primaryTeal),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Publish Announcement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAnnouncement(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: const Text('Remove this announcement from the public community newsfeed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _auth.deleteAnnouncement(id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: PROFILE SETTINGS
  // ==========================================
  Widget _buildProfileTab(ProviderProfile? profile, String displayName, String email, String uid) {
    return ProviderProfileTabView(
      profile: profile,
      displayName: displayName,
      email: email,
      uid: uid,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppTheme.primaryTeal),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedAppointmentItem {
  final Reservation? reservation;
  final Booking? booking;
  final RequestStatus effectiveStatus;
  final DateTime dateTime;
  final bool isReservation;

  bool get isEmergency => isReservation
      ? reservation!.visitType.toLowerCase().contains('emergency')
      : booking!.serviceName.toLowerCase().contains('emergency');

  bool get isCheckedIn => isReservation
      ? reservation!.checkedInAt != null
      : booking!.checkedInAt != null;

  _UnifiedAppointmentItem.fromReservation(this.reservation, this.effectiveStatus)
      : booking = null,
        dateTime = reservation!.requestedAt,
        isReservation = true;

  _UnifiedAppointmentItem.fromBooking(this.booking, this.effectiveStatus)
      : reservation = null,
        dateTime = booking!.scheduledAt,
        isReservation = false;
}

class ProviderProfileTabView extends StatefulWidget {
  final ProviderProfile? profile;
  final String displayName;
  final String email;
  final String uid;

  const ProviderProfileTabView({
    super.key,
    required this.profile,
    required this.displayName,
    required this.email,
    required this.uid,
  });

  @override
  State<ProviderProfileTabView> createState() => _ProviderProfileTabViewState();
}

class _ProviderProfileTabViewState extends State<ProviderProfileTabView> {
  final FirebaseService _auth = FirebaseService();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _specialtyCtrl;
  late final TextEditingController _bioCtrl;

  late String _openTime;
  late String _closeTime;
  late List<int> _openDays;
  late Set<String> _visitTypes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(
      text: p != null && p.displayName.isNotEmpty ? p.displayName : widget.displayName,
    );
    _phoneCtrl = TextEditingController(text: p?.phone ?? '');
    _cityCtrl = TextEditingController(text: p?.city ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _specialtyCtrl = TextEditingController(text: p?.specialty ?? '');
    _bioCtrl = TextEditingController(text: p?.bio ?? '');

    _openTime = p?.openTime ?? '08:00';
    _closeTime = p?.closeTime ?? '18:00';
    _openDays = p?.openDays ?? [1, 2, 3, 4, 5, 6];
    _visitTypes = (p?.visitTypes ?? ['Checkup', 'Vaccination', 'Consultation']).toSet();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _specialtyCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Edit Provider Profile',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Clinic / Veterinarian Name *'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(labelText: 'City *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(labelText: 'Address *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _specialtyCtrl,
            decoration: const InputDecoration(labelText: 'Specialty / Medical Focus'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Bio / Clinic Description'),
          ),
          const SizedBox(height: 16),

          const Text('Operating Hours Schedule', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OperatingHoursSelector(
            openTime: _openTime,
            closeTime: _closeTime,
            openDays: _openDays,
            onOpenTimeChanged: (val) => setState(() => _openTime = val),
            onCloseTimeChanged: (val) => setState(() => _closeTime = val),
            onOpenDaysChanged: (val) => setState(() => _openDays = val),
          ),
          const SizedBox(height: 16),

          const Text('Consultation Types Handled', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: const ['Checkup', 'Vaccination', 'Consultation', 'Follow-up', 'Emergency', 'Other'].map((type) {
              final isSelected = _visitTypes.contains(type);
              return FilterChip(
                label: Text(type),
                selected: isSelected,
                selectedColor: AppTheme.primaryTealLight,
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _visitTypes.add(type);
                    } else {
                      _visitTypes.remove(type);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Save Profile Details',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC62828),
                side: const BorderSide(color: Color(0xFFEF9A9A), width: 1.5),
                backgroundColor: const Color(0xFFFFEBEE),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.logout, size: 20),
              label: const Text(
                'Log Out of Vet / Clinic Portal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final updated = ProviderProfile(
      id: widget.uid,
      role: widget.profile?.role ?? UserRole.vet,
      displayName: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      specialty: _specialtyCtrl.text.trim().isNotEmpty ? _specialtyCtrl.text.trim() : null,
      visitTypes: _visitTypes.toList(),
      openTime: _openTime,
      closeTime: _closeTime,
      openDays: _openDays,
      hoursLabel: ProviderProfile.computeHoursLabel(_openDays, _openTime, _closeTime),
      active: true,
      createdAt: widget.profile?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await _auth.saveProviderProfile(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully! 🐾'), backgroundColor: AppTheme.primaryTeal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
