import 'package:flutter/material.dart';
import '../../models/provider_profile.dart';
import '../../models/service_offering.dart';
import '../../models/user_role.dart';
import '../../services/firebase_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/boutique_animations.dart';
import 'reservation_form_screen.dart';
import 'booking_form_screen.dart';

class ProviderDetailScreen extends StatefulWidget {
  final ProviderProfile provider;
  const ProviderDetailScreen({super.key, required this.provider});

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  final FirebaseService _db = FirebaseService();

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final isVet = p.role == UserRole.vet;
    final accentColor = isVet ? AppTheme.vetAccent : AppTheme.clinicAccent;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          p.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        backgroundColor: AppTheme.ownerAccent,
        foregroundColor: Colors.white,
        actions: const [
          ThemeModeToggleButton(iconColor: Colors.white),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card with Teal Gradient
            FadeInSlide(
              direction: SlideDirection.down,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.tealHeaderGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: AppTheme.softShadow,
                ),
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Hero(
                      tag: 'provider_avatar_${p.id}',
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Icon(
                          isVet ? Icons.medical_services_outlined : Icons.local_hospital_outlined,
                          size: 34,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  p.role.displayName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OpenStatusPill(provider: p, compact: true),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: Colors.white,
                            ),
                          ),
                          if (p.specialty != null && p.specialty!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              p.specialty!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),

          // Provider Contact & Hours Card
          FadeInSlide(
            delay: const Duration(milliseconds: 70),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.borderLight),
                boxShadow: AppTheme.cardShadow,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _infoRow(Icons.location_city, 'City', p.city.isNotEmpty ? p.city : 'Not specified'),
                  const Divider(),
                  _infoRow(Icons.place_outlined, 'Address', p.address.isNotEmpty ? p.address : 'Not specified'),
                  const Divider(),
                  _infoRow(Icons.phone_outlined, 'Phone', p.phone.isNotEmpty ? p.phone : 'Not specified'),
                  const Divider(),
                  _infoRow(Icons.schedule, 'Hours', p.hoursLabel.isNotEmpty ? p.hoursLabel : 'Mon-Sat • 8:00 AM - 6:00 PM'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bio
          if (p.bio.isNotEmpty) ...[
            const Text('About', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            FadeInSlide(
              delay: const Duration(milliseconds: 100),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderLight),
                  boxShadow: AppTheme.cardShadow,
                ),
                padding: const EdgeInsets.all(14),
                child: Text(
                  p.bio,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppTheme.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Section 1: Consultation / Visit Reservation
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.cardShadow,
            ),
            padding: const EdgeInsets.all(16),
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
                      child: const Icon(Icons.calendar_month_outlined, color: AppTheme.primaryTeal, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Consultation & Visit',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          Text(
                            'Reserve a time slot for checkup or clinical visit',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (p.visitTypes.isNotEmpty) ...[
                  const Text('Visit Types Handled:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: p.visitTypes.map((type) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTealLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, size: 13, color: AppTheme.primaryTeal),
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
                  const SizedBox(height: 14),
                ],
                BouncingScale(
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ReservationFormScreen(vet: p)),
                        );
                      },
                      icon: const Icon(Icons.event_available, size: 18),
                      label: const Text('Reserve a Consultation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Section 2: Services Catalog
          const Text('Offered Clinic Services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
            StreamBuilder<List<ServiceOffering>>(
              stream: _db.getClinicServices(p.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Could not load services: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                }
                final allServices = snapshot.data!;
                final activeServices = allServices.where((s) => s.active).toList();

                if (activeServices.isEmpty) {
                  return Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: const Center(
                      child: Text(
                        'No catalog services currently published by this provider.\nYou can still reserve a general consultation above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeServices.length,
                  itemBuilder: (context, index) {
                    final s = activeServices[index];
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
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                      ),
                                    ),
                                    Text(
                                      '\$${s.price.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.terracottaLight,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        s.category.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.terracotta),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.schedule, size: 13, color: AppTheme.textSecondary),
                                    const SizedBox(width: 4),
                                    Text('${s.durationMinutes} mins', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                  ],
                                ),
                                if (s.description.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(s.description, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
                                ],
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: BouncingScale(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => BookingFormScreen(clinic: p, service: s),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.bookmark_add, size: 16),
                                      label: const Text('Book Service', style: TextStyle(fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryTeal,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
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
