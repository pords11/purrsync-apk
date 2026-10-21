import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/announcement.dart';
import '../../models/cat.dart';
import '../../models/provider_profile.dart';
import '../../models/service_offering.dart';
import '../../models/booking.dart';
import '../../services/firebase_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/map_utils.dart';
import '../../utils/time_utils.dart';
import '../../widgets/boutique_animations.dart';
import '../add_cat_screen.dart';

class BookingFormScreen extends StatefulWidget {
  final ProviderProfile clinic;
  final ServiceOffering? service;
  final Booking? existingBooking;

  const BookingFormScreen({
    super.key,
    required this.clinic,
    this.service,
    this.existingBooking,
  });

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _db = FirebaseService();

  String? _selectedCatId;
  final List<Cat> _latestCats = [];
  ServiceOffering? _selectedService;
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
    _selectedService = widget.service;
    final b = widget.existingBooking;
    if (b != null) {
      _selectedDate = DateTime(b.scheduledAt.year, b.scheduledAt.month, b.scheduledAt.day);
      _selectedTime = TimeOfDay(hour: b.scheduledAt.hour, minute: b.scheduledAt.minute);
      _notesController.text = b.notes;
      _loadOccupiedSlots(_selectedDate!);
    }
  }

  Future<void> _loadOccupiedSlots(DateTime date) async {
    setState(() => _isLoadingSlots = true);
    final slots = await _db.getAcceptedSlotsForProvider(widget.clinic.id, date);
    if (mounted) {
      setState(() {
        _occupiedSlots = slots;
        _isLoadingSlots = false;
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = now.add(const Duration(days: 180));

    final openDays = widget.clinic.openDays.isNotEmpty ? widget.clinic.openDays : [1, 2, 3, 4, 5, 6];

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
    final initial = _selectedTime ?? TimeUtils.parseHm(widget.clinic.openTime);

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

    if (widget.existingBooking == null && _selectedCatId == null) {
      setState(() => _errorMessage = 'Please select a cat.');
      return;
    }

    if (_selectedService == null && widget.existingBooking == null) {
      setState(() => _errorMessage = 'Please select a service.');
      return;
    }

    if (_selectedDate == null) {
      setState(() => _errorMessage = 'Please choose a booking date.');
      return;
    }

    if (_selectedTime == null) {
      setState(() => _errorMessage = 'Please choose a booking time via the clock dial.');
      return;
    }

    final catStr = (_selectedService?.category ?? '').toLowerCase();
    final nameStr = (_selectedService?.name ?? widget.existingBooking?.serviceName ?? '').toLowerCase();
    final isEmergencyService = catStr.contains('emergency') || nameStr.contains('emergency');
    final isCustomService = catStr.startsWith('other') || nameStr.contains('custom');
    if ((isEmergencyService || isCustomService) && _notesController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = isEmergencyService
            ? 'Please describe your cat\'s emergency symptoms and urgency so the clinic can evaluate priority.'
            : 'Please describe your custom service request details and any symptoms.';
      });
      return;
    }

    final scheduledDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    if (scheduledDateTime.isBefore(DateTime.now())) {
      setState(() => _errorMessage = 'Scheduled time cannot be in the past.');
      return;
    }

    final duration = _selectedService?.durationMinutes ?? widget.existingBooking?.serviceDurationMinutes ?? 30;

    // Validate within clinic hours including duration
    if (!TimeUtils.isWithinHours(scheduledDateTime, widget.clinic, durationMinutes: duration)) {
      setState(() {
        _errorMessage = 'Selected slot (with $duration mins duration) falls outside of clinic operating hours (${widget.clinic.hoursLabel}).';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Validate slot availability against accepted bookings/reservations
      final isOccupied = await _db.isProviderSlotOccupied(
        widget.clinic.id,
        scheduledDateTime,
        duration,
        excludeId: widget.existingBooking?.id,
      );
      if (isOccupied) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'This time slot is already booked and accepted. Please choose a different time.';
        });
        return;
      }

      final user = _db.getCurrentUser();
      if (user == null) throw Exception('Not signed in');

      if (widget.existingBooking != null) {
        // Edit pending booking
        final sId = _selectedService?.id ?? widget.existingBooking!.serviceId;
        final sName = _selectedService?.name ?? widget.existingBooking!.serviceName;
        final sPrice = _selectedService?.price ?? widget.existingBooking!.servicePrice;
        final sDuration = _selectedService?.durationMinutes ?? widget.existingBooking!.serviceDurationMinutes;

        await _db.updateBookingDetails(
          widget.existingBooking!.id,
          serviceId: sId,
          serviceName: sName,
          servicePrice: sPrice,
          serviceDurationMinutes: sDuration,
          scheduledAt: scheduledDateTime,
          notes: _notesController.text.trim(),
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking updated! 🐾'), backgroundColor: Colors.green),
          );
        }
      } else {
        // New booking
        final cat = _latestCats.firstWhere(
          (c) => c.id == _selectedCatId,
          orElse: () => throw AppException('Selected cat not found.'),
        );
        final b = Booking(
          id: '',
          ownerId: user.uid,
          ownerName: user.displayName ?? (user.email?.split('@').first ?? 'Cat Owner'),
          catId: cat.id,
          catName: cat.name,
          catBreed: cat.breed,
          clinicId: widget.clinic.id,
          clinicName: widget.clinic.displayName,
          serviceId: _selectedService!.id,
          serviceName: _selectedService!.name,
          servicePrice: _selectedService!.price,
          serviceDurationMinutes: _selectedService!.durationMinutes,
          scheduledAt: scheduledDateTime,
          notes: _notesController.text.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _db.createBooking(b);

        if (mounted) {
          await showPurrSyncSuccessOverlay(
            context,
            title: 'Booking Requested!',
            subtitle: '${widget.clinic.displayName} received your service booking.',
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
    final isEditing = widget.existingBooking != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Service Booking' : 'Book Clinic Service', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.clinicAccent,
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
                    // Clinic info card
                    Card(
                      color: AppTheme.clinicAccent.withValues(alpha: 0.08),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppTheme.clinicAccent.withValues(alpha: 0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.clinicAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.local_hospital, color: AppTheme.clinicAccent, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.clinic.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Hours: ${widget.clinic.hoursLabel}',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Open Clinic in Google Maps',
                              onPressed: () => MapUtils.openDirections(
                                destinationAddress: '${widget.clinic.address}, ${widget.clinic.city}',
                                clinicName: widget.clinic.displayName,
                                context: context,
                              ),
                              icon: const Icon(Icons.directions, color: Color(0xFF4285F4)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Latest Clinic Announcement Banner (Informational Only)
                    _buildLatestProviderAnnouncementBanner(widget.clinic.id),
                    const SizedBox(height: 20),

                    // Cat selection
                    if (!isEditing) ...[
                      const Text('Select Cat *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      StreamBuilder<List<Cat>>(
                        stream: _db.getCats(user.uid),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator(color: AppTheme.clinicAccent));
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
                                      label: const Text('Add Cat First'),
                                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.clinicAccent, foregroundColor: Colors.white),
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
                              prefixIcon: const Icon(Icons.pets, color: AppTheme.clinicAccent),
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
                        'Cat: ${widget.existingBooking!.catName} (${widget.existingBooking!.catBreed})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Service Details Card
                    if (_selectedService != null) ...[
                      const Text('Service to Book', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: AppTheme.borderLight),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.clinicAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.medical_services, color: AppTheme.clinicAccent),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_selectedService!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_selectedService!.category.toUpperCase()} • ${_selectedService!.durationMinutes} mins',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${_selectedService!.price.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.clinicAccent),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (isEditing) ...[
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: AppTheme.borderLight),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Service: ${widget.existingBooking!.serviceName} - \$${widget.existingBooking!.servicePrice.toStringAsFixed(2)} (${widget.existingBooking!.serviceDurationMinutes} mins)',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Date & Clock Time pickers
                    const Text('Scheduled Date & Time *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
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
                                prefixIcon: const Icon(Icons.calendar_today, color: AppTheme.clinicAccent),
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
                                prefixIcon: const Icon(Icons.access_time, color: AppTheme.clinicAccent),
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
                      const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.clinicAccent))),
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
                                    timeStr,
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFBF360C)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Prominent Symptoms / Custom Service Request Box
                    Builder(
                      builder: (context) {
                        final catStr = (_selectedService?.category ?? '').toLowerCase();
                        final nameStr = (_selectedService?.name ?? widget.existingBooking?.serviceName ?? '').toLowerCase();
                        final isEmergencyService = catStr.contains('emergency') || nameStr.contains('emergency');
                        final isCustomService = catStr.startsWith('other') || nameStr.contains('custom');
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isEmergencyService || isCustomService)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isEmergencyService ? const Color(0xFFFFEBEE) : AppTheme.primaryTealLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isEmergencyService ? Colors.red.shade300 : AppTheme.primaryTeal.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isEmergencyService ? Icons.emergency : Icons.info_outline,
                                      color: isEmergencyService ? Colors.red.shade800 : AppTheme.primaryTealDark,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isEmergencyService
                                            ? 'Emergency Service Triage: Please describe your cat\'s symptoms, onset, and urgency so the clinic can evaluate priority before accepting or declining.'
                                            : 'Custom Service Request: Please describe the specific procedure, symptoms, or custom requirements for the clinic.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isEmergencyService ? Colors.red.shade900 : AppTheme.primaryTealDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            TextFormField(
                              controller: _notesController,
                              maxLength: 500,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: isEmergencyService
                                    ? 'Emergency Symptoms & Urgency Description *'
                                    : isCustomService
                                        ? 'Custom Service Details & Symptoms *'
                                        : 'Symptoms / Request Description / Special Instructions',
                                hintText: isEmergencyService
                                    ? 'Describe urgent symptoms, breathing, injury, or condition in detail...'
                                    : 'Describe any symptoms, service details, or special instructions for the clinic...',
                                prefixIcon: Icon(
                                  isEmergencyService ? Icons.medical_information : Icons.note_alt_outlined,
                                  color: isEmergencyService ? Colors.red.shade700 : AppTheme.clinicAccent,
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        );
                      },
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
                            backgroundColor: AppTheme.clinicAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  isEditing ? 'Save Changes' : 'Confirm Service Booking',
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
