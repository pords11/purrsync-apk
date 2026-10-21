import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/cat.dart';
import '../../models/provider_profile.dart';
import '../../models/reservation.dart';
import '../../models/request_status.dart';
import '../../services/firebase_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/map_utils.dart';
import '../../widgets/boutique_animations.dart';

enum TriageUrgency {
  emergency,
  urgent,
  routine,
}

class SmartTriageScreen extends StatefulWidget {
  final Cat? initialCat;
  const SmartTriageScreen({super.key, this.initialCat});

  @override
  State<SmartTriageScreen> createState() => _SmartTriageScreenState();
}

class _SmartTriageScreenState extends State<SmartTriageScreen> {
  final FirebaseService _auth = FirebaseService();
  String? _selectedCatId;
  List<Cat> _cats = [];
  bool _isLoadingCats = true;

  final Set<String> _selectedSymptoms = {};
  bool _isAutoMatching = false;
  ProviderProfile? _matchedProvider;
  DateTime? _matchedDateTime;
  String? _matchedVisitType;
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _criticalSymptoms = [
    {
      'id': 'flutd',
      'label': 'Straining to Urinate (FLUTD / Blockage Risk)',
      'desc': 'Life-threatening emergency in male cats. Immediate catheterization required.',
      'icon': Icons.warning_rounded,
    },
    {
      'id': 'breathing',
      'label': 'Open-Mouth / Labored Breathing',
      'desc': 'Feline respiratory distress. Requires immediate oxygen therapy.',
      'icon': Icons.air_rounded,
    },
    {
      'id': 'poison',
      'label': 'Toxic Ingestion / Poisoning (Lilies, Permethrin)',
      'desc': 'Acute organ failure risk. Immediate triage necessary.',
      'icon': Icons.coronavirus_rounded,
    },
    {
      'id': 'trauma',
      'label': 'Severe Trauma / Heavy Bleeding / Fall',
      'desc': 'High-rise syndrome, bite wounds, or vehicle trauma.',
      'icon': Icons.medical_services_rounded,
    },
    {
      'id': 'seizure',
      'label': 'Seizure / Sudden Collapse / Paralysis',
      'desc': 'Neurological crisis or aortic thromboembolism (saddle thrombus).',
      'icon': Icons.flash_on_rounded,
    },
  ];

  final List<Map<String, dynamic>> _clinicalSymptoms = [
    {
      'id': 'vomiting',
      'label': 'Frequent Vomiting or Severe Diarrhea',
      'desc': 'Rapid dehydration risk.',
      'icon': Icons.sick_outlined,
    },
    {
      'id': 'anorexia',
      'label': 'Lethargy & Inappetence (>24 Hours)',
      'desc': 'Risk of feline hepatic lipidosis.',
      'icon': Icons.sentiment_very_dissatisfied_outlined,
    },
    {
      'id': 'flu',
      'label': 'Sneezing / Eye & Nasal Discharge (Cat Flu)',
      'desc': 'Upper respiratory viral infection.',
      'icon': Icons.masks_outlined,
    },
    {
      'id': 'ear_skin',
      'label': 'Intense Ear Scratching / Hair Loss / Ringworm',
      'desc': 'Parasitic mites or fungal infection.',
      'icon': Icons.pets_outlined,
    },
  ];

  final List<Map<String, dynamic>> _preventativeItems = [
    {
      'id': 'vax_booster',
      'label': 'Core Vaccination Booster (FVRCP / Anti-Rabies)',
      'desc': 'Routine annual immunization.',
      'icon': Icons.vaccines_outlined,
    },
    {
      'id': 'kapon',
      'label': 'Kapon / Spay-Neuter Consultation',
      'desc': 'Surgical sterilization and pre-op screening.',
      'icon': Icons.healing_outlined,
    },
    {
      'id': 'deworm',
      'label': 'Broad-Spectrum Deworming & Flea Treatment',
      'desc': 'Quarterly parasite prophylaxis.',
      'icon': Icons.bug_report_outlined,
    },
    {
      'id': 'wellness',
      'label': 'Comprehensive Wellness & Physical Exam',
      'desc': 'Preventative nose-to-tail check-up.',
      'icon': Icons.health_and_safety_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    final user = _auth.getCurrentUser();
    if (user != null) {
      final stream = _auth.getCats(user.uid);
      final catsList = await stream.first;
      if (mounted) {
        setState(() {
          _cats = catsList;
          _isLoadingCats = false;
          if (widget.initialCat != null && _cats.any((c) => c.id == widget.initialCat!.id)) {
            _selectedCatId = widget.initialCat!.id;
          } else if (_cats.length == 1) {
            _selectedCatId = _cats.first.id;
          }
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingCats = false);
    }
  }

  TriageUrgency get _currentUrgency {
    final hasCritical = _selectedSymptoms.any((id) => _criticalSymptoms.any((s) => s['id'] == id));
    if (hasCritical) return TriageUrgency.emergency;

    final hasClinical = _selectedSymptoms.any((id) => _clinicalSymptoms.any((s) => s['id'] == id));
    if (hasClinical) return TriageUrgency.urgent;

    return TriageUrgency.routine;
  }

  void _toggleSymptom(String id) {
    setState(() {
      if (_selectedSymptoms.contains(id)) {
        _selectedSymptoms.remove(id);
      } else {
        _selectedSymptoms.add(id);
      }
      _matchedProvider = null;
    });
  }

  Future<void> _autoMatchClinicAndSlot() async {
    if (_selectedCatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a cat first.')),
      );
      return;
    }

    if (_selectedSymptoms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one symptom or purpose.')),
      );
      return;
    }

    setState(() => _isAutoMatching = true);

    try {
      final providers = await _auth.getAllProviders().first;
      if (providers.isEmpty) {
        throw AppException('No registered veterinary clinics available.');
      }

      final urgency = _currentUrgency;
      ProviderProfile bestClinic;

      if (urgency == TriageUrgency.emergency) {
        final emergencyCapable = providers.where((p) => p.visitTypes.contains('Emergency')).toList();
        bestClinic = emergencyCapable.isNotEmpty ? emergencyCapable.first : providers.first;
      } else if (_selectedSymptoms.contains('kapon')) {
        final surgeryCapable = providers.where((p) => p.visitTypes.any((v) => v.toLowerCase().contains('surg'))).toList();
        bestClinic = surgeryCapable.isNotEmpty ? surgeryCapable.first : providers.first;
      } else {
        bestClinic = providers.first;
      }

      DateTime slotTime;
      String visitType;

      if (urgency == TriageUrgency.emergency) {
        slotTime = DateTime.now(); // ASAP Immediate Triage
        visitType = 'Emergency';
      } else if (_selectedSymptoms.contains('vax_booster') || _selectedSymptoms.contains('deworm')) {
        slotTime = DateTime.now().add(const Duration(hours: 2));
        visitType = 'Vaccination';
      } else if (_selectedSymptoms.contains('kapon')) {
        slotTime = DateTime.now().add(const Duration(days: 1, hours: 9));
        visitType = 'Surgery';
      } else {
        slotTime = DateTime.now().add(const Duration(hours: 3));
        visitType = 'Check-up';
      }

      if (mounted) {
        setState(() {
          _matchedProvider = bestClinic;
          _matchedDateTime = slotTime;
          _matchedVisitType = visitType;
          _isAutoMatching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAutoMatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-match failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmAndBook() async {
    if (_matchedProvider == null || _matchedDateTime == null || _selectedCatId == null) return;

    final cat = _cats.firstWhere((c) => c.id == _selectedCatId);
    final user = _auth.getCurrentUser();
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final symptomLabels = _selectedSymptoms.map((id) {
        final all = [..._criticalSymptoms, ..._clinicalSymptoms, ..._preventativeItems];
        final match = all.firstWhere((item) => item['id'] == id, orElse: () => {'label': id});
        return match['label'] as String;
      }).join(', ');

      final notes = 'Automated Smart Triage: [$symptomLabels]. Current Weight: ${cat.weight} kg (${cat.genderDisplay}, ${cat.ageDisplay}).';

      final reservation = Reservation(
        id: '',
        ownerId: user.uid,
        ownerName: user.displayName ?? 'Pet Owner',
        catId: cat.id,
        catName: cat.name,
        catBreed: cat.breed,
        vetId: _matchedProvider!.id,
        vetName: _matchedProvider!.displayName,
        visitType: _matchedVisitType ?? 'Check-up',
        requestedAt: _matchedDateTime!,
        notes: notes,
        status: RequestStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _auth.createReservation(reservation);

      if (mounted) {
        await showPurrSyncSuccessOverlay(
          context,
          title: 'Booking Confirmed!',
          subtitle: 'Smart triage ticket sent to ${_matchedProvider!.displayName}.',
        );
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final urgency = _currentUrgency;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text('Automated Smart Triage', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingCats
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step 1: Select Cat
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1. Select Patient Cat',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 10),
                          if (_cats.isEmpty)
                            const Text('No cats found. Please add a cat first.', style: TextStyle(color: Colors.red))
                          else
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCatId,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.pets, color: AppTheme.primaryTeal),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              hint: const Text('Choose a cat'),
                              items: _cats.map((c) {
                                return DropdownMenuItem(
                                  value: c.id,
                                  child: Text('${c.name} (${c.genderDisplay} • ${c.weight} kg)'),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() {
                                _selectedCatId = val;
                                _matchedProvider = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Step 2: Select Symptoms / Reason
                  const Text(
                    '2. Clinical Reason / Symptoms',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 8),

                  // Critical Emergency Group
                  _buildSymptomSection(
                    title: '🚨 Feline Emergency Red Flags (Life-Threatening)',
                    subtitle: 'Immediate triage lane will be auto-assigned',
                    items: _criticalSymptoms,
                    headerColor: AppTheme.statusDanger,
                  ),
                  const SizedBox(height: 12),

                  // Clinical Concerns Group
                  _buildSymptomSection(
                    title: '⚠️ Acute Clinical Concerns',
                    subtitle: 'Requires same-day veterinary diagnosis',
                    items: _clinicalSymptoms,
                    headerColor: AppTheme.statusWarning,
                  ),
                  const SizedBox(height: 12),

                  // Preventative Group
                  _buildSymptomSection(
                    title: '💉 Preventative Care & Wellness',
                    subtitle: 'Vaccine boosters, kapon consultation, deworming',
                    items: _preventativeItems,
                    headerColor: AppTheme.primaryTeal,
                  ),
                  const SizedBox(height: 18),

                  // Live Urgency Evaluator Banner
                  _buildUrgencyBanner(urgency),
                  const SizedBox(height: 20),

                  // Auto-Match Trigger Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: (_selectedSymptoms.isEmpty || _isAutoMatching) ? null : _autoMatchClinicAndSlot,
                      icon: _isAutoMatching
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.flash_on, color: Colors.white),
                      label: Text(
                        _isAutoMatching ? 'Analyzing & Matching Best Clinic...' : 'Auto-Find Best Clinic & Available Slot',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: urgency == TriageUrgency.emergency ? AppTheme.statusDanger : AppTheme.primaryTeal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                    ),
                  ),

                  // Step 3: Match Result Preview Card
                  if (_matchedProvider != null) ...[
                    const SizedBox(height: 20),
                    _buildMatchedResultCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSymptomSection({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required Color headerColor,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 16, color: headerColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: headerColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((item) {
                final id = item['id'] as String;
                final isSelected = _selectedSymptoms.contains(id);
                return FilterChip(
                  label: Text(item['label'] as String, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  avatar: Icon(item['icon'] as IconData, size: 16, color: isSelected ? Colors.white : AppTheme.primaryTeal),
                  selected: isSelected,
                  selectedColor: headerColor.withValues(alpha: 0.9),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary),
                  backgroundColor: AppTheme.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isSelected ? headerColor : AppTheme.borderLight),
                  ),
                  onSelected: (_) => _toggleSymptom(id),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgencyBanner(TriageUrgency urgency) {
    Color bg;
    Color border;
    IconData icon;
    String title;
    String desc;

    switch (urgency) {
      case TriageUrgency.emergency:
        bg = AppTheme.statusDanger.withValues(alpha: 0.12);
        border = AppTheme.statusDanger;
        icon = Icons.emergency_rounded;
        title = '🚨 TRIAGE STATUS: EMERGENCY (IMMEDIATE / ASAP)';
        desc = 'High-urgency feline crisis. The system will pre-fill the earliest triage lane and pin your ticket to the top of the clinic inbox.';
        break;
      case TriageUrgency.urgent:
        bg = AppTheme.statusWarning.withValues(alpha: 0.12);
        border = AppTheme.statusWarning;
        icon = Icons.alarm_on_rounded;
        title = '⚠️ TRIAGE STATUS: URGENT SAME-DAY CONSULT';
        desc = 'Feline symptoms require same-day diagnosis. The system will auto-match available clinical slots today.';
        break;
      case TriageUrgency.routine:
        bg = AppTheme.statusSafe.withValues(alpha: 0.12);
        border = AppTheme.statusSafe;
        icon = Icons.check_circle_outline;
        title = '🐾 TRIAGE STATUS: PREVENTATIVE & ROUTINE CARE';
        desc = 'Routine wellness / vaccine booster. The system will select a convenient, conflict-free schedule.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: border, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: border, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchedResultCard() {
    final p = _matchedProvider!;
    final dateStr = _matchedDateTime != null
        ? DateFormat('EEEE, MMM d, yyyy • h:mm a').format(_matchedDateTime!)
        : 'Immediate / ASAP';

    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.task_alt, color: AppTheme.statusSafe, size: 22),
                SizedBox(width: 8),
                Text(
                  'Automated Clinic & Slot Match',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(p.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text('${p.address}, ${p.city}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
              ],
            ),
            const SizedBox(height: 8),

            // Google Maps 1-Tap Directions Button
            InkWell(
              onTap: () => MapUtils.openDirections(destinationAddress: '${p.address}, ${p.city}', clinicName: p.displayName, context: context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF4285F4).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions, color: Color(0xFF4285F4), size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Preview Route in Google Maps',
                      style: TextStyle(color: Color(0xFF4285F4), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryTealLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Visit Type:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      Text(_matchedVisitType ?? 'Check-up', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Auto-Assigned Slot:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      Text(dateStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Confirm 1-Tap Booking Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _confirmAndBook,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle, color: Colors.white),
                label: Text(
                  _isSubmitting ? 'Confirming Automated Booking...' : 'Confirm & Instant Auto-Book (1-Tap)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
