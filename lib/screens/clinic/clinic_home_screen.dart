import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firebase_service.dart';
import '../../models/provider_profile.dart';
import '../../models/user_role.dart';
import '../../models/request_status.dart';
import '../../models/service_offering.dart';
import '../../models/booking.dart';
import '../../models/announcement.dart';
import '../../widgets/operating_hours_selector.dart';
import '../../utils/app_theme.dart';
import '../../widgets/boutique_animations.dart';

class ClinicHomeScreen extends StatefulWidget {
  const ClinicHomeScreen({super.key});

  @override
  State<ClinicHomeScreen> createState() => _ClinicHomeScreenState();
}

class _ClinicHomeScreenState extends State<ClinicHomeScreen> {
  final FirebaseService _auth = FirebaseService();
  int _currentIndex = 0;

  // Bookings filter: 'pending', 'accepted', 'history'
  String _bookingFilter = 'pending';

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
            Icon(Icons.local_hospital_outlined, color: Colors.white),
            SizedBox(width: 8),
            Text('PurrSync Clinic', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: AppTheme.clinicAccent,
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
            return const Center(child: CircularProgressIndicator(color: AppTheme.clinicAccent));
          }
          final profile = snapshot.data;
          final displayName = profile?.displayName.isNotEmpty == true
              ? profile!.displayName
              : (user.displayName ?? 'Veterinary Clinic');

          return IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(user.uid, user.email ?? '', displayName, profile),
              _buildBookingsTab(user.uid),
              _buildServicesTab(user.uid, displayName),
              _buildAnnouncementsTab(user.uid, displayName),
              _buildProfileTab(profile, displayName, user.email ?? '', user.uid),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppTheme.clinicAccent,
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
            icon: Icon(Icons.bookmark_outline),
            activeIcon: Icon(Icons.bookmark),
            label: 'Bookings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.medical_services_outlined),
            activeIcon: Icon(Icons.medical_services),
            label: 'Services',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            activeIcon: Icon(Icons.campaign),
            label: 'Announcements',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.business_outlined),
            activeIcon: Icon(Icons.business),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 0: HOME / OVERVIEW
  // ==========================================

  Widget _buildHomeTab(String clinicId, String email, String displayName, ProviderProfile? profile) {
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
                    color: AppTheme.clinicAccent.withValues(alpha: 0.12),
                    child: const Icon(Icons.local_hospital, size: 30, color: AppTheme.clinicAccent),
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
                          color: AppTheme.clinicAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'CLINIC PORTAL',
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

          // Real-time booking stats stream
          StreamBuilder<List<Booking>>(
            stream: _auth.getClinicBookings(clinicId),
            builder: (context, snapshot) {
              int pending = 0;
              int accepted = 0;
              int total = 0;
              List<Booking> todayBookings = [];

              if (snapshot.hasData) {
                final list = snapshot.data!;
                total = list.length;
                pending = list.where((b) => b.status == RequestStatus.pending).length;
                accepted = list.where((b) => b.status == RequestStatus.accepted).length;

                final now = DateTime.now();
                todayBookings = list.where((b) {
                  return b.status == RequestStatus.accepted &&
                      b.scheduledAt.year == now.year &&
                      b.scheduledAt.month == now.month &&
                      b.scheduledAt.day == now.day;
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
                      _buildStatBox('Total', total.toString(), Icons.list_alt, AppTheme.clinicAccent),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Today's Appointments",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      if (todayBookings.isNotEmpty)
                        Text(
                          '${todayBookings.length} scheduled',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (todayBookings.isEmpty)
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
                          'No accepted bookings scheduled for today.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...todayBookings.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final b = entry.value;
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
                              title: Text('${b.catName} • ${b.serviceName}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              subtitle: Text('Owner: ${b.ownerName} • ${DateFormat('hh:mm a').format(b.scheduledAt)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
            'Clinic Information',
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
                _infoRow(Icons.location_on, 'Address', profile?.address.isNotEmpty == true ? profile!.address : 'Not specified'),
                const Divider(color: AppTheme.dividerColor),
                _infoRow(Icons.phone, 'Phone', profile?.phone.isNotEmpty == true ? profile!.phone : 'Not specified'),
                const Divider(color: AppTheme.dividerColor),
                _infoRow(
                  Icons.access_time,
                  'Hours',
                  profile?.hoursLabel.isNotEmpty == true ? profile!.hoursLabel : 'Not specified',
                ),
              ],
            ),
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
  // TAB 1: BOOKINGS INBOX
  // ==========================================

  Widget _buildBookingsTab(String clinicId) {
    return Column(
      children: [
        // Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              FilterChip(
                selected: _bookingFilter == 'pending',
                label: const Text('Pending'),
                selectedColor: const Color(0xFFFDEFD7),
                checkmarkColor: const Color(0xFFC77700),
                labelStyle: TextStyle(
                  color: _bookingFilter == 'pending' ? const Color(0xFF8A5200) : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _bookingFilter == 'pending' ? const Color(0xFFE5A038) : AppTheme.borderLight)),
                onSelected: (val) => setState(() => _bookingFilter = 'pending'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _bookingFilter == 'accepted',
                label: const Text('Accepted'),
                selectedColor: AppTheme.primaryTealLight,
                checkmarkColor: AppTheme.primaryTeal,
                labelStyle: TextStyle(
                  color: _bookingFilter == 'accepted' ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _bookingFilter == 'accepted' ? AppTheme.primaryTeal : AppTheme.borderLight)),
                onSelected: (val) => setState(() => _bookingFilter = 'accepted'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _bookingFilter == 'history',
                label: const Text('History'),
                selectedColor: const Color(0xFFE8ECEF),
                checkmarkColor: AppTheme.clinicAccent,
                labelStyle: TextStyle(
                  color: _bookingFilter == 'history' ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _bookingFilter == 'history' ? AppTheme.clinicAccent : AppTheme.borderLight)),
                onSelected: (val) => setState(() => _bookingFilter = 'history'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Booking>>(
            stream: _auth.getClinicBookings(clinicId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text('Error loading bookings: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.clinicAccent));
              }

              final all = snapshot.data!;
              final now = DateTime.now();
              final filtered = all.where((b) {
                final eff = effectiveStatus(
                  stored: b.status,
                  start: b.scheduledAt,
                  end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
                  now: now,
                );
                if (_bookingFilter == 'pending') return eff == RequestStatus.pending;
                if (_bookingFilter == 'accepted') return eff == RequestStatus.accepted;
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
                        'No $_bookingFilter bookings',
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
                  final booking = filtered[index];
                  return FadeInSlide(
                    delay: Duration(milliseconds: 35 * index),
                    child: BouncingScale(
                      child: _buildBookingCard(booking),
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

  Widget _buildBookingCard(Booking b) {
    final now = DateTime.now();
    final effStatus = effectiveStatus(
      stored: b.status,
      start: b.scheduledAt,
      end: b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes)),
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
                        color: AppTheme.clinicAccent.withValues(alpha: 0.1),
                        child: const Icon(Icons.pets, color: AppTheme.clinicAccent, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        b.catName,
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
          const SizedBox(height: 10),
          Text(
            'Owner: ${b.ownerName}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Service: ${b.serviceName}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${b.serviceDurationMinutes}m • \$${b.servicePrice.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                DateFormat('EEE, MMM d • hh:mm a').format(b.scheduledAt),
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
          if (b.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Notes: ${b.notes}', style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
            ),
          ],
          if (b.providerNote != null && b.providerNote!.isNotEmpty) ...[
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
                'Your note: ${b.providerNote}',
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
                  onPressed: () => _showDeclineDialog(b.id),
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
                  onPressed: () => _updateBookingStatus(b.id, RequestStatus.accepted),
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
                  onPressed: () => _showDeclineDialog(b.id),
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
                  onPressed: () => _updateBookingStatus(b.id, RequestStatus.completed),
                  icon: const Icon(Icons.done_all, size: 16, color: Colors.white),
                  label: const Text('Mark Completed', style: TextStyle(color: Colors.white, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.clinicAccent,
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

  Future<void> _updateBookingStatus(String id, RequestStatus newStatus, {String? note}) async {
    try {
      await _auth.respondToBooking(id, newStatus, providerNote: note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking updated to ${newStatus.label}')),
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
          SnackBar(content: Text('Error updating booking: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeclineDialog(String id) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Decline Booking'),
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
                  hintText: 'e.g. Service slot unavailable, please pick another date/time.',
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
                _updateBookingStatus(
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
  // TAB 2: SERVICES CATALOG
  // ==========================================

  Widget _buildServicesTab(String clinicId, String clinicName) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<ServiceOffering>>(
        stream: _auth.getClinicServices(clinicId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading services: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.clinicAccent));
          }

          final services = snapshot.data!;
          if (services.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.medical_services_outlined, size: 72, color: AppTheme.textTertiary),
                  const SizedBox(height: 16),
                  const Text('No services in your catalog', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Add services such as Vaccinations, Grooming, Surgery, or Consultations.', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _openServiceDialog(clinicId, clinicName),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Add Service', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.clinicAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            itemBuilder: (context, index) {
              final s = services[index];
              return FadeInSlide(
                delay: Duration(milliseconds: 35 * index),
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
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.clinicAccent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.clinicAccent.withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      s.category,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.clinicAccent),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: s.active ? const Color(0xFFE8F5E9) : const Color(0xFFF1F3F5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      s.active ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: s.active ? const Color(0xFF2E7D32) : AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: AppTheme.textSecondary),
                              onPressed: () => _openServiceDialog(clinicId, clinicName, existing: s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Color(0xFFD32F2F)),
                              onPressed: () => _confirmDeleteService(s.id),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        if (s.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(s.description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.3)),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 16, color: AppTheme.textSecondary),
                                const SizedBox(width: 4),
                                Text('${s.durationMinutes} mins', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                              ],
                            ),
                            Text(
                              '\$${s.price.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.clinicAccent),
                            ),
                          ],
                        ),
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
        onPressed: () => _openServiceDialog(clinicId, clinicName),
        backgroundColor: AppTheme.clinicAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _confirmDeleteService(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service?'),
        content: const Text('Are you sure you want to permanently delete this service offering?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _auth.deleteService(id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Service deleted')),
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

  void _openServiceDialog(String clinicId, String clinicName, {ServiceOffering? existing}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.toStringAsFixed(2) : '');
    String category = existing?.category ?? 'Consultation';
    int duration = existing?.durationMinutes ?? 30;
    bool active = existing?.active ?? true;

    const categories = [
      'Consultation',
      'Vaccination',
      'Grooming',
      'Surgery',
      'Dental',
      'Laboratory',
      'Boarding',
      'Other',
    ];

    const durations = [15, 30, 45, 60, 90, 120];

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
                            existing == null ? 'Add New Service' : 'Edit Service',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Service Name *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Service name is required' : null,
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                        items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) {
                          if (val != null) setSheetState(() => category = val);
                        },
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: priceCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Price (\$) *',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Price is required';
                                final p = double.tryParse(v.trim());
                                if (p == null || p < 0) return 'Invalid price';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: duration,
                              decoration: const InputDecoration(labelText: 'Duration', border: OutlineInputBorder()),
                              items: durations.map((d) => DropdownMenuItem(value: d, child: Text('$d mins'))).toList(),
                              onChanged: (val) {
                                if (val != null) setSheetState(() => duration = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Description / Notes', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        title: const Text('Active Service'),
                        subtitle: const Text('Available for pet owners to book'),
                        value: active,
                        onChanged: (val) => setSheetState(() => active = val),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;

                            final price = double.parse(priceCtrl.text.trim());
                            final service = ServiceOffering(
                              id: existing?.id ?? '',
                              providerId: clinicId,
                              providerName: clinicName,
                              name: nameCtrl.text.trim(),
                              description: descCtrl.text.trim(),
                              category: category,
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
                                  SnackBar(content: Text(existing == null ? 'Service added!' : 'Service updated!')),
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
                            backgroundColor: AppTheme.clinicAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            existing == null ? 'Add Service' : 'Save Changes',
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
  // TAB 3: ANNOUNCEMENTS & EVENTS
  // ==========================================

  Widget _buildAnnouncementsTab(String clinicId, String clinicName) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<Announcement>>(
        stream: _auth.getMyAnnouncements(clinicId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading announcements: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.clinicAccent));
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
                  const Text('Share updates, spay/neuter drives, and clinic announcements!', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _openAnnouncementDialog(clinicId, clinicName),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Create Announcement', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.clinicAccent,
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
                  child: _buildAnnouncementCard(item, clinicId, clinicName),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAnnouncementDialog(clinicId, clinicName),
        backgroundColor: AppTheme.clinicAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildAnnouncementCard(Announcement item, String clinicId, String clinicName) {
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
                onPressed: () => _openAnnouncementDialog(clinicId, clinicName, existing: item),
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

  void _openAnnouncementDialog(String clinicId, String clinicName, {Announcement? existing}) {
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
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

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
                        decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a title' : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: bodyCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Details / Content *', border: OutlineInputBorder()),
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
                              authorId: clinicId,
                              authorRole: UserRole.clinic.toValue(),
                              authorName: clinicName,
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
                            backgroundColor: AppTheme.clinicAccent,
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
  // TAB 4: PROFILE & EDIT PROFILE
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
              color: AppTheme.clinicAccent.withValues(alpha: 0.12),
              child: const Icon(Icons.business, size: 44, color: AppTheme.clinicAccent),
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
              label: const Text('Edit Clinic Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.clinicAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),

          _buildProfileTile(Icons.badge_outlined, 'Account Role', 'Veterinary Clinic'),
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
            color: AppTheme.clinicAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.clinicAccent, size: 20),
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

    String openT = profile?.openTime ?? '08:00';
    String closeT = profile?.closeTime ?? '18:00';
    List<int> openD = profile?.openDays.isNotEmpty == true ? List.from(profile!.openDays) : [1, 2, 3, 4, 5, 6];

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
                            'Edit Clinic Profile',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Clinic Name *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Clinic name is required' : null,
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
                        controller: bioCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Bio / Description', border: OutlineInputBorder()),
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
                              role: UserRole.clinic,
                              displayName: nameCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                              city: cityCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              bio: bioCtrl.text.trim(),
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
                                  const SnackBar(content: Text('Clinic profile updated!')),
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
                            backgroundColor: AppTheme.clinicAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          Icon(icon, size: 20, color: AppTheme.clinicAccent),
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

