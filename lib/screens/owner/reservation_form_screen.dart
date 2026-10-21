import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/announcement.dart';
import '../../models/cat.dart';
import '../../models/provider_profile.dart';
import '../../models/reservation.dart';
import '../../services/firebase_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/map_utils.dart';
import '../../utils/time_utils.dart';
import '../../widgets/boutique_animations.dart';
import '../add_cat_screen.dart';

class ReservationFormScreen extends StatefulWidget {
  final ProviderProfile vet;
  final Reservation? existingReservation;

  const ReservationFormScreen({
    super.key,
    required this.vet,
    this.existingReservation,
  });

  @override
  State<ReservationFormScreen> createState() => _ReservationFormScreenState();
}


class _ReservationFormScreenState extends State<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _db = FirebaseService();

  String? _selectedCatId;
  final List<Cat> _latestCats = [];
  String _selectedVisitType = 'Checkup';
  final TextEditingController _customVisitTypeController = TextEditingController();
  bool _isImmediateEmergency = true;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final TextEditingController _notesController = TextEditingController();

  List<Map<String, dynamic>> _occupiedSlots = [];
  bool _isLoadingSlots = false;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final res = widget.existingReservation;
    if (res != null) {
      if (res.visitType.startsWith('Other: ')) {
        _selectedVisitType = 'Other';
        _customVisitTypeController.text = res.visitType.substring('Other: '.length);
      } else {
        _selectedVisitType = res.visitType;
      }
      _isImmediateEmergency = false;
      _selectedDate = DateTime(res.requestedAt.year, res.requestedAt.month, res.requestedAt.day);
      _selectedTime = TimeOfDay(hour: res.requestedAt.hour, minute: res.requestedAt.minute);
      _notesController.text = res.notes;
      _loadOccupiedSlots(_selectedDate!);
    } else {
      if (widget.vet.visitTypes.isNotEmpty) {
        _selectedVisitType = widget.vet.visitTypes.first;
      }
      if (_selectedVisitType == 'Emergency') {
        _isImmediateEmergency = true;
        final now = DateTime.now();
        _selectedDate = DateTime(now.year, now.month, now.day);
        _selectedTime = TimeOfDay.fromDateTime(now);
      }
    }
  }

  Future<void> _loadOccupiedSlots(DateTime date) async {
    setState(() => _isLoadingSlots = true);
    final slots = await _db.getAcceptedSlotsForProvider(widget.vet.id, date);
    if (mounted) {
      setState(() {
        _occupiedSlots = slots;
        _isLoadingSlots = false;
      });
    }
  }

  @override
  void dispose() {
    _customVisitTypeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = now.add(const Duration(days: 180));

    final openDays = widget.vet.openDays.isNotEmpty ? widget.vet.openDays : [1, 2, 3, 4, 5, 6];

    // Find valid initial date
    DateTime initial = _selectedDate ?? first;
    if (!openDays.contains(initial.weekday)) {
      for (int i = 0; i < 7; i++) {
        final d = first.add(Duration(days: i));
        if (openDays.contains(d.weekday)) {
          initial = d;
          break;
        }
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (day) => openDays.contains(day.weekday),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _errorMessage = null;
      });
      _loadOccupiedSlots(picked);
    }
  }

  Future<void> _pickTime() async {
    final initial = _selectedTime ?? TimeUtils.parseHm(widget.vet.openTime);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dialOnly,
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _errorMessage = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (widget.existingReservation == null && _selectedCatId == null) {
      setState(() => _errorMessage = 'Please select a cat for this appointment.');
      return;
    }

    String finalVisitType = _selectedVisitType;
    if (_selectedVisitType == 'Other') {
      final customSpec = _customVisitTypeController.text.trim();
      if (customSpec.isEmpty) {
        setState(() => _errorMessage = 'Please specify custom details / name for the "Other" visit type.');
        return;
      }
      finalVisitType = 'Other: $customSpec';
    }

    final isEmergency = _selectedVisitType == 'Emergency';
    final isCustom = _selectedVisitType == 'Other';
    if ((isEmergency || isCustom) && _notesController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = isEmergency
            ? 'Please describe the emergency symptoms and urgency so the veterinarian can evaluate your request.'
            : 'Please provide a description of your custom visit request.';
      });
      return;
    }

    DateTime appointmentDateTime;
    if (isEmergency && _isImmediateEmergency) {
      // Immediate / ASAP urgent triage: default to current time (+5 mins buffer so it remains active in pending queue)
      appointmentDateTime = DateTime.now().add(const Duration(minutes: 5));
    } else {
      if (_selectedDate == null) {
        setState(() => _errorMessage = 'Please choose an appointment date.');
        return;
      }

      if (_selectedTime == null) {
        setState(() => _errorMessage = 'Please choose an appointment time using the clock dial.');
        return;
      }

      appointmentDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      if (appointmentDateTime.isBefore(DateTime.now())) {
        setState(() => _errorMessage = 'Appointment time cannot be in the past.');
        return;
      }

      // Validate within provider hours (for non-immediate appointments)
      if (!isEmergency && !TimeUtils.isWithinHours(appointmentDateTime, widget.vet)) {
        setState(() {
          _errorMessage = 'Selected time is outside of ${widget.vet.displayName}\'s hours (${widget.vet.hoursLabel}).';
        });
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      // Validate slot availability against accepted bookings/reservations (bypassed for Immediate Emergency triage)
      if (!isEmergency) {
        final isOccupied = await _db.isProviderSlotOccupied(
          widget.vet.id,
          appointmentDateTime,
          30,
          excludeId: widget.existingReservation?.id,
        );
        if (isOccupied) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'This time slot is already booked and accepted. Please choose a different time.';
          });
          return;
        }
      }
      final user = _db.getCurrentUser();
      if (user == null) throw Exception('Not signed in');

      if (widget.existingReservation != null) {
        // Edit existing pending reservation
        await _db.updateReservationDetails(
          widget.existingReservation!.id,
          visitType: finalVisitType,
          requestedAt: appointmentDateTime,
          notes: _notesController.text.trim(),
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reservation updated! 🐾'), backgroundColor: Colors.green),
          );
        }
      } else {
        // Create new reservation
        final cat = _latestCats.firstWhere(
          (c) => c.id == _selectedCatId,
          orElse: () => throw AppException('Selected cat not found.'),
        );
        final res = Reservation(
          id: '',
          ownerId: user.uid,
          ownerName: user.displayName ?? (user.email?.split('@').first ?? 'Cat Owner'),
          catId: cat.id,
          catName: cat.name,
          catBreed: cat.breed,
          vetId: widget.vet.id,
          vetName: widget.vet.displayName,
          visitType: finalVisitType,
          requestedAt: appointmentDateTime,
          notes: _notesController.text.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _db.createReservation(res);

        if (mounted) {
          await showPurrSyncSuccessOverlay(
            context,
            title: 'Reservation Sent!',
            subtitle: '${widget.vet.displayName} will review your request shortly.',
          );
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _db.getCurrentUser();
    final isEditing = widget.existingReservation != null;

    final baseOptions = widget.vet.visitTypes.isNotEmpty
        ? List<String>.from(widget.vet.visitTypes)
        : ['Checkup', 'Vaccination', 'Consultation', 'Follow-up', 'Emergency', 'Other'];
    if (!baseOptions.contains('Emergency')) baseOptions.add('Emergency');
    if (!baseOptions.contains('Other')) baseOptions.add('Other');
    final visitOptions = baseOptions;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Reservation' : 'Reserve Vet Visit', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('Not signed in'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Vet header banner
                    Card(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.08),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.medical_services, color: AppTheme.primaryTeal, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.vet.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Hours: ${widget.vet.hoursLabel}',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Open Clinic in Google Maps',
                              onPressed: () => MapUtils.openDirections(
                                destinationAddress: '${widget.vet.address}, ${widget.vet.city}',
                                clinicName: widget.vet.displayName,
                                context: context,
                              ),
                              icon: const Icon(Icons.directions, color: Color(0xFF4285F4)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Latest Clinic Announcement Banner (Informational Only)
                    _buildLatestProviderAnnouncementBanner(widget.vet.id),
                    const SizedBox(height: 20),

                    // Cat selector (only on new reservation)
                    if (!isEditing) ...[
                      const Text('Select Cat *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      StreamBuilder<List<Cat>>(
                        stream: _db.getCats(user.uid),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                          }
                          final cats = snapshot.data!;
                          // Keep _latestCats in sync without setState (we're in build)
                          _latestCats.clear();
                          _latestCats.addAll(cats);
                          if (cats.isEmpty) {
                            return Card(
                              color: Colors.red.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    const Text('You have not added any cats yet!'),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => const AddCatScreen()),
                                        );
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add a Cat First'),
                                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Auto-preselect if only one cat
                          if (cats.length == 1 && _selectedCatId == null) {
                            _selectedCatId = cats.first.id;
                          }

                          final ids = cats.map((c) => c.id).toSet();
                          final safeValue = ids.contains(_selectedCatId) ? _selectedCatId : null;

                          return DropdownButtonFormField<String>(
                            initialValue: safeValue,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.pets, color: AppTheme.primaryTeal),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            hint: const Text('Choose a cat'),
                            items: cats.map((cat) {
                              return DropdownMenuItem<String>(
                                value: cat.id,
                                child: Text('${cat.name} (${cat.breed.isNotEmpty ? cat.breed : 'Cat'} • ${cat.ageDisplay})'),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedCatId = val),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'Cat: ${widget.existingReservation!.catName} (${widget.existingReservation!.catBreed})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Visit Type
                    const Text('Visit Type *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: visitOptions.contains(_selectedVisitType) ? _selectedVisitType : visitOptions.first,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.health_and_safety, color: AppTheme.primaryTeal),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      items: visitOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedVisitType = val;
                            _errorMessage = null;
                            if (val == 'Emergency') {
                              _isImmediateEmergency = true;
                              final now = DateTime.now();
                              _selectedDate = DateTime(now.year, now.month, now.day);
                              _selectedTime = TimeOfDay.fromDateTime(now);
                            }
                          });
                        }
                      },
                    ),
                    if (_selectedVisitType == 'Other') ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _customVisitTypeController,
                        decoration: InputDecoration(
                          labelText: 'Specify Custom Details / Name *',
                          hintText: 'e.g., Post-Op Suture Removal, Second Opinion',
                          prefixIcon: const Icon(Icons.edit_note, color: AppTheme.primaryTeal),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Emergency Immediate / ASAP Schedule Mode & Clinic Phone Coordination
                    if (_selectedVisitType == 'Emergency') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.red.shade400, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.phone_in_talk, color: Colors.red.shade800, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Immediate Travel & Triage Coordination',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Call ${widget.vet.displayName} immediately while in transit so the clinical team can prepare emergency triage:',
                              style: TextStyle(fontSize: 12.5, color: Colors.red.shade900),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.call, size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      widget.vet.phone.isNotEmpty
                                          ? 'Clinic Hotline: ${widget.vet.phone}'
                                          : 'Clinic Hotline: Contact ${widget.vet.displayName} directly at ${widget.vet.address}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: Colors.red.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Emergency Schedule Mode *',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    selected: _isImmediateEmergency,
                                    selectedColor: Colors.red.shade700,
                                    label: Text(
                                      'Immediate / ASAP (Urgent Triage)',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: _isImmediateEmergency ? Colors.white : AppTheme.textPrimary,
                                      ),
                                    ),
                                    onSelected: (sel) {
                                      setState(() {
                                        _isImmediateEmergency = true;
                                        _errorMessage = null;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  selected: !_isImmediateEmergency,
                                  selectedColor: AppTheme.primaryTeal,
                                  label: Text(
                                    'Pick Time',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: !_isImmediateEmergency ? Colors.white : AppTheme.textPrimary,
                                    ),
                                  ),
                                  onSelected: (sel) {
                                    setState(() {
                                      _isImmediateEmergency = false;
                                      _errorMessage = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (_isImmediateEmergency) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.bolt, size: 16, color: Colors.red.shade800),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Defaults to RIGHT NOW (${DateFormat('MMM d, yyyy • hh:mm a').format(DateTime.now())}) and pins your request to the top of the Vet\'s inbox.',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.red.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Date & Clock Time pickers (hidden when Immediate/ASAP Emergency is active)
                    if (!(_selectedVisitType == 'Emergency' && _isImmediateEmergency)) ...[
                      const Text('Appointment Date & Time *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Date',
                                  prefixIcon: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: Text(
                                  _selectedDate != null
                                      ? _selectedDate!.toLocal().toString().split(' ')[0]
                                      : 'Pick Date',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _selectedDate != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _pickTime,
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Clock Time',
                                  prefixIcon: const Icon(Icons.access_time, color: AppTheme.primaryTeal),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: Text(
                                  _selectedTime != null
                                      ? _selectedTime!.format(context)
                                      : 'Clock Dial',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _selectedTime != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isLoadingSlots) ...[
                        const SizedBox(height: 8),
                        const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal))),
                      ] else if (_occupiedSlots.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFE082)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.event_busy, color: Color(0xFFF57F17), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Already Booked / Occupied on this Date:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFE65100)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: _occupiedSlots.map((s) {
                                  final start = s['start'] as DateTime;
                                  final end = s['end'] as DateTime;
                                  final timeStr = '${DateFormat('hh:mm a').format(start)} - ${DateFormat('hh:mm a').format(end)}';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE0B2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$timeStr (Booked)',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFBF360C)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    // Prominent Emergency / Custom Request Evaluation Box
                    if (_selectedVisitType == 'Emergency' || _selectedVisitType == 'Other') ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _selectedVisitType == 'Emergency'
                              ? const Color(0xFFFFEBEE)
                              : AppTheme.primaryTealLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedVisitType == 'Emergency'
                                ? Colors.red.shade300
                                : AppTheme.primaryTeal.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _selectedVisitType == 'Emergency' ? Icons.emergency : Icons.info_outline,
                              color: _selectedVisitType == 'Emergency' ? Colors.red.shade800 : AppTheme.primaryTealDark,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _selectedVisitType == 'Emergency'
                                    ? 'Emergency Triage Required: Please describe your cat\'s symptoms, when they started, and urgency level so the veterinarian can evaluate priority before accepting or declining.'
                                    : 'Custom Visit Request: Please provide clear details and symptoms below so the veterinarian can prepare or respond appropriately.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedVisitType == 'Emergency' ? Colors.red.shade900 : AppTheme.primaryTealDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Notes / Symptoms (max 500)
                    TextFormField(
                      controller: _notesController,
                      maxLength: 500,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: _selectedVisitType == 'Emergency'
                            ? 'Emergency Symptoms & Urgency Description *'
                            : _selectedVisitType == 'Other'
                                ? 'Custom Request Details & Symptoms *'
                                : 'Symptoms / Notes / Reason for Visit (max 500 chars)',
                        hintText: _selectedVisitType == 'Emergency'
                            ? 'Describe breathing, lethargy, injury, vomiting, or urgent symptoms in detail...'
                            : 'Share any symptoms, behavioral changes, or special concerns...',
                        prefixIcon: Icon(
                          _selectedVisitType == 'Emergency' ? Icons.medical_information : Icons.note_alt_outlined,
                          color: _selectedVisitType == 'Emergency' ? Colors.red.shade700 : AppTheme.primaryTeal,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    BouncingScale(
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  isEditing ? 'Save Changes' : 'Confirm & Request Reservation',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLatestProviderAnnouncementBanner(String providerId) {
    return StreamBuilder<List<Announcement>>(
      stream: _db.getPublishedAnnouncements(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final now = DateTime.now();
        final active = snapshot.data!.where((item) {
          if (item.authorId != providerId) return false;
          if (!item.published) return false;
          if (item.expiresAt != null && item.expiresAt!.isBefore(now)) return false;
          if (item.type == 'event' && item.eventDate != null) {
            final dayAfter = DateTime(item.eventDate!.year, item.eventDate!.month, item.eventDate!.day)
                .add(const Duration(days: 1));
            if (dayAfter.isBefore(now)) return false;
          }
          return true;
        }).toList();

        if (active.isEmpty) return const SizedBox.shrink();

        // Prioritize Schedule / Hours Update announcements first, then newest
        active.sort((a, b) {
          final aSched = a.type.toLowerCase().contains('schedule') || a.type.toLowerCase().contains('hours');
          final bSched = b.type.toLowerCase().contains('schedule') || b.type.toLowerCase().contains('hours');
          if (aSched != bSched) return aSched ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });

        final latest = active.first;
        final isScheduleNotice =
            latest.type.toLowerCase().contains('schedule') || latest.type.toLowerCase().contains('hours');

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isScheduleNotice ? const Color(0xFFFFF8E1) : AppTheme.primaryTealLight.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isScheduleNotice ? const Color(0xFFFFCC80) : AppTheme.primaryTeal.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isScheduleNotice ? Icons.event_repeat_outlined : Icons.campaign_outlined,
                color: isScheduleNotice ? const Color(0xFFE65100) : AppTheme.primaryTealDark,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isScheduleNotice
                          ? 'Clinic Schedule Notice • ${latest.title}'
                          : 'Clinic Notice • ${latest.title}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: isScheduleNotice ? const Color(0xFFE65100) : AppTheme.primaryTealDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      latest.body,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                        height: 1.35,
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
  }
}
