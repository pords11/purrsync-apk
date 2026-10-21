import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cat.dart';
import '../services/firebase_service.dart';
import '../utils/app_theme.dart';
import 'boutique_animations.dart';

class ClinicalEMRDialog extends StatefulWidget {
  final String appointmentId;
  final bool isBooking;
  final String catId;
  final String catName;
  final String ownerId;
  final String clinicName;
  final String? ownerName;
  final String? catBreed;
  final double? initialWeight;
  final double? baseServiceFeePhp;
  final String? initialVisitNotes;

  const ClinicalEMRDialog({
    super.key,
    required this.appointmentId,
    required this.isBooking,
    required this.catId,
    required this.catName,
    required this.ownerId,
    required this.clinicName,
    this.ownerName,
    this.catBreed,
    this.initialWeight,
    this.baseServiceFeePhp,
    this.initialVisitNotes,
  });

  @override
  State<ClinicalEMRDialog> createState() => _ClinicalEMRDialogState();
}

class _ClinicalEMRDialogState extends State<ClinicalEMRDialog> {
  final FirebaseService _auth = FirebaseService();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _tempController = TextEditingController(text: '38.6');
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _medicineController = TextEditingController();

  Cat? _loadedCat;
  double? _baselineWeight;
  String _selectedVaccine = 'None';
  bool _isKaponPerformed = false;
  DateTime? _followUpDate;
  bool _isSaving = false;

  final List<String> _vaccineOptions = [
    'None',
    '4-in-1 Core Vaccine (FVRCP)',
    'Anti-Rabies Core Shot',
    'Broad-Spectrum Deworming',
    'Feline Leukemia (FeLV) Shot',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialWeight != null && widget.initialWeight! > 0) {
      _baselineWeight = widget.initialWeight;
      _weightController.text = widget.initialWeight!.toStringAsFixed(1);
    }
    _weightController.addListener(() {
      if (mounted) setState(() {});
    });
    _tempController.addListener(() {
      if (mounted) setState(() {});
    });
    _medicineController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadCatBaseline();
  }

  Future<void> _loadCatBaseline() async {
    final cat = await _auth.getCatById(widget.catId);
    if (!mounted || cat == null) return;
    setState(() {
      _loadedCat = cat;
      if (cat.weight > 0) {
        _baselineWeight = cat.weight;
        if (_weightController.text.trim().isEmpty) {
          _weightController.text = cat.weight.toStringAsFixed(1);
        }
      }
    });
  }

  @override
  void dispose() {
    _weightController.dispose();
    _tempController.dispose();
    _diagnosisController.dispose();
    _medicineController.dispose();
    super.dispose();
  }

  double get _effectiveWeightKg {
    final parsed = double.tryParse(_weightController.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    if (_baselineWeight != null && _baselineWeight! > 0) return _baselineWeight!;
    return 4.0;
  }

  double get _computedTotalBillPhp {
    double total = widget.baseServiceFeePhp != null && widget.baseServiceFeePhp! > 0
        ? widget.baseServiceFeePhp!
        : 550.0;
    if (_selectedVaccine == '4-in-1 Core Vaccine (FVRCP)') {
      total += 850.0;
    } else if (_selectedVaccine == 'Anti-Rabies Core Shot') {
      total += 450.0;
    } else if (_selectedVaccine == 'Broad-Spectrum Deworming') {
      total += 300.0;
    } else if (_selectedVaccine == 'Feline Leukemia (FeLV) Shot') {
      total += 950.0;
    }
    if (_isKaponPerformed) {
      total += 1800.0;
    }
    if (_medicineController.text.trim().isNotEmpty) {
      total += 350.0;
    }
    return total;
  }

  void _applyQuickDiagnosis(String text) {
    setState(() {
      if (_diagnosisController.text.trim().isEmpty) {
        _diagnosisController.text = text;
      } else {
        _diagnosisController.text = '${_diagnosisController.text.trim()} $text';
      }
    });
  }

  void _applyAutoDosage({
    required String drugName,
    required double mgPerKg,
    required double concentrationMgPerMl,
    required String frequencyAndDuration,
  }) {
    final w = _effectiveWeightKg;
    final totalMg = w * mgPerKg;
    final totalMl = totalMg / concentrationMgPerMl;
    final rxLine =
        '$drugName (${concentrationMgPerMl.toStringAsFixed(concentrationMgPerMl < 1 ? 1 : 0)}mg/mL): '
        'Give ${totalMl.toStringAsFixed(2)} mL (${totalMg.toStringAsFixed(1)} mg for ${w.toStringAsFixed(1)}kg cat) '
        '$frequencyAndDuration';
    setState(() {
      _medicineController.text = rxLine;
    });
  }

  Future<void> _submitEMR() async {
    final diagnosis = _diagnosisController.text.trim();
    if (diagnosis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter or tap a clinical diagnosis summary.')),
      );
      return;
    }

    final weight = double.tryParse(_weightController.text.trim());
    final temp = double.tryParse(_tempController.text.trim());

    setState(() => _isSaving = true);

    try {
      await _auth.completeAppointmentWithClinicalEMR(
        appointmentId: widget.appointmentId,
        isBooking: widget.isBooking,
        catId: widget.catId,
        ownerId: widget.ownerId,
        clinicName: widget.clinicName,
        catName: _loadedCat?.name ?? widget.catName,
        ownerName: widget.ownerName,
        catBreed: _loadedCat?.breed ?? widget.catBreed,
        diagnosisNotes: diagnosis,
        recordedWeightKg: weight,
        temperatureCelsius: temp,
        vaccineTypeGiven: _selectedVaccine == 'None' ? null : _selectedVaccine,
        isKaponPerformed: _isKaponPerformed,
        prescribedMedicine: _medicineController.text.trim().isEmpty ? null : _medicineController.text.trim(),
        followUpDate: _followUpDate,
        totalBillPhp: _computedTotalBillPhp,
      );

      if (mounted) {
        Navigator.pop(context, true);
        await showPurrSyncSuccessOverlay(
          context,
          title: 'Smart EMR Synced!',
          subtitle: _followUpDate != null
              ? 'Records updated & Follow-Up auto-booked for ${DateFormat('MMM d').format(_followUpDate!)}.'
              : 'Clinical records, weight & receipt synced to ${widget.catName}.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving EMR: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildWeightDeltaBadge() {
    final current = double.tryParse(_weightController.text.trim());
    if (current == null || current <= 0 || _baselineWeight == null || _baselineWeight! <= 0) {
      return const SizedBox.shrink();
    }
    final diff = current - _baselineWeight!;
    final pct = (diff / _baselineWeight!) * 100;
    if (diff.abs() < 0.05) {
      return _statusBadge(
        icon: Icons.check_circle_outline,
        text: 'Stable weight vs baseline (${_baselineWeight!.toStringAsFixed(1)} kg)',
        color: AppTheme.statusSafe,
      );
    }
    final isLoss = diff < 0;
    final isRapidLoss = pct <= -8.0;
    return _statusBadge(
      icon: isRapidLoss ? Icons.warning_amber_rounded : (isLoss ? Icons.trending_down : Icons.trending_up),
      text: isRapidLoss
          ? '⚠️ Rapid Weight Loss: ${diff.toStringAsFixed(2)} kg (${pct.toStringAsFixed(1)}%) vs ${_baselineWeight!.toStringAsFixed(1)} kg'
          : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)} kg (${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%) vs previous ${_baselineWeight!.toStringAsFixed(1)} kg',
      color: isRapidLoss ? Colors.red.shade700 : AppTheme.primaryTealDark,
    );
  }

  Widget _buildTempAssessmentBadge() {
    final temp = double.tryParse(_tempController.text.trim());
    if (temp == null || temp <= 0) return const SizedBox.shrink();
    if (temp > 39.2) {
      return _statusBadge(
        icon: Icons.thermostat_rounded,
        text: '🚨 Pyrexia / Fever Detected (${temp.toStringAsFixed(1)}°C > 39.2°C normal max)',
        color: Colors.red.shade700,
      );
    }
    if (temp < 38.0) {
      return _statusBadge(
        icon: Icons.ac_unit_rounded,
        text: '⚠️ Hypothermia Alert (${temp.toStringAsFixed(1)}°C < 38.0°C normal min)',
        color: Colors.orange.shade800,
      );
    }
    return _statusBadge(
      icon: Icons.verified_rounded,
      text: '✅ Normothermic Feline Temp (${temp.toStringAsFixed(1)}°C within 38.1–39.2°C)',
      color: AppTheme.statusSafe,
    );
  }

  Widget _statusBadge({required IconData icon, required String text, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wKg = _effectiveWeightKg;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.medical_services_rounded, color: AppTheme.primaryTeal, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Smart Automated Clinical EMR',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Patient: ${widget.catName} • Auto-Syncs Vitals, Rx, Follow-Up & Bill',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Auto-loaded Patient Baseline Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTealLight.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pets_rounded, size: 18, color: AppTheme.primaryTealDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadedCat != null
                            ? 'Auto-Loaded Chart: ${_loadedCat!.name} • ${_loadedCat!.breed.isNotEmpty ? _loadedCat!.breed : 'Domestic'} • ${_loadedCat!.genderDisplay} • ${_loadedCat!.ageDisplay} • Last Weight: ${_loadedCat!.weight.toStringAsFixed(1)} kg'
                            : 'Patient: ${widget.catName} (${widget.catBreed ?? 'Feline'}) • Ready for automated clinical charting',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.primaryTealDark),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 22),

              // 1. Vital Signs: Weight + Temperature
              const Text(
                '1. Automated Vital Signs & Weight Delta Evaluator',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Weight Today (kg)',
                        hintText: 'e.g. 4.2',
                        prefixIcon: const Icon(Icons.monitor_weight_outlined, color: AppTheme.primaryTeal, size: 19),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _tempController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Rectal/Ear Temp (°C)',
                        hintText: '38.6',
                        prefixIcon: const Icon(Icons.thermostat_outlined, color: AppTheme.primaryTeal, size: 19),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              _buildWeightDeltaBadge(),
              _buildTempAssessmentBadge(),
              const SizedBox(height: 14),

              // 2. Vaccine administered
              const Text(
                '2. Vaccine / Prophylaxis Administered (Auto-Schedules Next Due Date)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedVaccine,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.vaccines_outlined, color: AppTheme.primaryTeal, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _vaccineOptions
                    .map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedVaccine = val;
                    if (val != 'None') {
                      _applyQuickDiagnosis('Administered $val with zero immediate adverse reaction.');
                    }
                  });
                },
              ),
              const SizedBox(height: 14),

              // 3. Kapon / Spay-Neuter toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _isKaponPerformed ? AppTheme.primaryTeal.withValues(alpha: 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isKaponPerformed ? AppTheme.primaryTeal : AppTheme.borderLight),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.healing_outlined, color: AppTheme.primaryTeal, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Kapon / Spay-Neuter Completed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            'Auto-updates Cat gender to Spayed/Neutered & sets 7-day post-op check',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isKaponPerformed,
                      activeThumbColor: AppTheme.primaryTeal,
                      onChanged: (val) {
                        setState(() {
                          _isKaponPerformed = val;
                          if (val) {
                            _followUpDate ??= DateTime.now().add(const Duration(days: 7));
                            _applyQuickDiagnosis(
                              'Kapon surgical sterilization completed under general anesthesia. Incision closed cleanly.',
                            );
                            _applyAutoDosage(
                              drugName: 'Meloxicam Oral NSAID',
                              mgPerKg: 0.05,
                              concentrationMgPerMl: 0.5,
                              frequencyAndDuration: 'orally once daily x 3 days for post-op pain',
                            );
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Clinical Diagnosis & Treatment
              const Text(
                '3. Clinical Diagnosis & Discharge Notes (1-Tap Templates) *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _quickChip(
                    'Normal Wellness Exam',
                    () => _applyQuickDiagnosis('Routine physical exam normal. Clear lungs, healthy mucous membranes, alert demeanor.'),
                  ),
                  _quickChip(
                    'URI / Respiratory Protocol',
                    () => _applyQuickDiagnosis('Feline upper respiratory infection noted. SubQ hydration and antibiotic regimen initiated.'),
                  ),
                  _quickChip(
                    'GI / Deworming Protocol',
                    () => _applyQuickDiagnosis('Mild gastrointestinal parasitism/upset addressed with weight-calibrated oral anthelmintic.'),
                  ),
                  _quickChip(
                    'Dermatology / Otitis',
                    () => _applyQuickDiagnosis('Topical ear/skin cleansing performed; anti-parasitic and anti-inflammatory protocol started.'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _diagnosisController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter or tap clinical diagnosis, findings, and veterinarian treatment notes...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 14),

              // 5. Automated Feline Drug Dosage Calculator (mg/kg -> mL)
              Row(
                children: [
                  const Icon(Icons.calculate_outlined, size: 17, color: AppTheme.primaryTeal),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '4. Automated Feline Dosage Calculator (for ${wKg.toStringAsFixed(1)} kg Cat)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap any medication below to auto-compute exact mg & mL oral dose from patient weight:',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _quickChip(
                    '💊 Amox-Clav (12.5mg/kg)',
                    () => _applyAutoDosage(
                      drugName: 'Amoxicillin-Clavulanate',
                      mgPerKg: 12.5,
                      concentrationMgPerMl: 50.0,
                      frequencyAndDuration: 'orally every 12 hrs x 7 days',
                    ),
                  ),
                  _quickChip(
                    '💊 Doxycycline (10mg/kg)',
                    () => _applyAutoDosage(
                      drugName: 'Doxycycline Hyclate',
                      mgPerKg: 10.0,
                      concentrationMgPerMl: 25.0,
                      frequencyAndDuration: 'orally once daily x 14 days',
                    ),
                  ),
                  _quickChip(
                    '💊 Meloxicam Pain (0.05mg/kg)',
                    () => _applyAutoDosage(
                      drugName: 'Meloxicam Oral NSAID',
                      mgPerKg: 0.05,
                      concentrationMgPerMl: 0.5,
                      frequencyAndDuration: 'orally once daily x 3 days',
                    ),
                  ),
                  _quickChip(
                    '💊 Pyrantel Dewormer (20mg/kg)',
                    () => _applyAutoDosage(
                      drugName: 'Pyrantel Pamoate',
                      mgPerKg: 20.0,
                      concentrationMgPerMl: 50.0,
                      frequencyAndDuration: 'single oral dose today (repeat in 14d)',
                    ),
                  ),
                  _quickChip(
                    '💊 Prednisolone (1mg/kg)',
                    () => _applyAutoDosage(
                      drugName: 'Prednisolone Oral',
                      mgPerKg: 1.0,
                      concentrationMgPerMl: 5.0,
                      frequencyAndDuration: 'orally once daily x 5 days',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _medicineController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Auto-calculated mL/mg prescription or custom home care instructions...',
                  prefixIcon: const Icon(Icons.medication_outlined, color: AppTheme.primaryTeal, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),

              // 6. Automated Follow-up Appointment Scheduler
              const Text(
                '5. Auto-Schedule Follow-Up Appointment (Creates Confirmed Booking)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _quickChip(
                    '📅 +7 Days (Post-Op / Recheck)',
                    () => setState(() => _followUpDate = DateTime.now().add(const Duration(days: 7))),
                  ),
                  _quickChip(
                    '📅 +14 Days (Deworm / Course End)',
                    () => setState(() => _followUpDate = DateTime.now().add(const Duration(days: 14))),
                  ),
                  _quickChip(
                    '📅 +21 Days (Next Kitten Booster)',
                    () => setState(() => _followUpDate = DateTime.now().add(const Duration(days: 21))),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.event_repeat, color: AppTheme.primaryTeal, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _followUpDate == null
                          ? 'Follow-Up: None (Tap chip above to auto-book next visit)'
                          : '⚡ Auto-Booking Follow-Up on: ${DateFormat('EEE, MMM d, yyyy').format(_followUpDate!)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _followUpDate != null ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _followUpDate ?? DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _followUpDate = picked);
                    },
                    child: Text(_followUpDate == null ? 'Pick Date' : 'Change'),
                  ),
                  if (_followUpDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _followUpDate = null),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 7. Automated Itemized Billing & Digital Receipt Summary
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 18, color: AppTheme.primaryTealDark),
                        SizedBox(width: 8),
                        Text(
                          'Auto-Computed Clinical Bill & E-Receipt:',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      '₱${_computedTotalBillPhp.toStringAsFixed(0)} PHP',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.primaryTealDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submitEMR,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.cloud_sync, color: Colors.white, size: 18),
                    label: Text(
                      _isSaving ? 'Syncing EMR...' : 'Complete & Auto-Sync EMR',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.08),
      side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.25)),
      onPressed: onTap,
    );
  }
}
