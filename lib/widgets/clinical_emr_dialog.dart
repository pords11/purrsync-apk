import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  final double? initialWeight;

  const ClinicalEMRDialog({
    super.key,
    required this.appointmentId,
    required this.isBooking,
    required this.catId,
    required this.catName,
    required this.ownerId,
    required this.clinicName,
    this.initialWeight,
  });

  @override
  State<ClinicalEMRDialog> createState() => _ClinicalEMRDialogState();
}

class _ClinicalEMRDialogState extends State<ClinicalEMRDialog> {
  final FirebaseService _auth = FirebaseService();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _medicineController = TextEditingController();

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
      _weightController.text = widget.initialWeight!.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _diagnosisController.dispose();
    _medicineController.dispose();
    super.dispose();
  }

  void _applyQuickDiagnosis(String text) {
    setState(() {
      if (_diagnosisController.text.trim().isEmpty) {
        _diagnosisController.text = text;
      } else {
        _diagnosisController.text += ' $text';
      }
    });
  }

  Future<void> _submitEMR() async {
    final diagnosis = _diagnosisController.text.trim();
    if (diagnosis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a clinical diagnosis or treatment summary.')),
      );
      return;
    }

    final weight = double.tryParse(_weightController.text.trim());

    setState(() => _isSaving = true);

    try {
      await _auth.completeAppointmentWithClinicalEMR(
        appointmentId: widget.appointmentId,
        isBooking: widget.isBooking,
        catId: widget.catId,
        ownerId: widget.ownerId,
        clinicName: widget.clinicName,
        diagnosisNotes: diagnosis,
        recordedWeightKg: weight,
        vaccineTypeGiven: _selectedVaccine == 'None' ? null : _selectedVaccine,
        isKaponPerformed: _isKaponPerformed,
        prescribedMedicine: _medicineController.text.trim().isEmpty ? null : _medicineController.text.trim(),
        followUpDate: _followUpDate,
      );

      if (mounted) {
        Navigator.pop(context, true);
        await showPurrSyncSuccessOverlay(
          context,
          title: 'EMR Synced!',
          subtitle: 'Clinical records auto-updated to ${widget.catName}.',
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppTheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
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
                          'Complete Visit & Auto-Sync EMR',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Patient: ${widget.catName} • Auto-updates Cat Profile',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // 1. Weight recorded
              const Text(
                '1. Patient Weight Measured Today (kg)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: 'e.g. 4.2',
                  suffixText: 'kg (Auto-syncs to Weight Graph)',
                  prefixIcon: const Icon(Icons.monitor_weight_outlined, color: AppTheme.primaryTeal, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),

              // 2. Vaccine administered
              const Text(
                '2. Vaccine / Prophylaxis Administered (Optional)',
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
                items: _vaccineOptions.map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedVaccine = val);
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
                          Text('Auto-updates gender to Neutered/Spayed', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isKaponPerformed,
                      activeThumbColor: AppTheme.primaryTeal,
                      onChanged: (val) => setState(() => _isKaponPerformed = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Clinical Diagnosis & Treatment
              const Text(
                '3. Clinical Diagnosis & Discharge Notes *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _quickChip('Normal Health Exam', () => _applyQuickDiagnosis('Routine physical exam normal. Clear lungs and bright alert demeanor.')),
                  _quickChip('Vaccine Given', () => _applyQuickDiagnosis('Vaccination administered smoothly. No immediate adverse reaction.')),
                  _quickChip('Kapon Done', () => _applyQuickDiagnosis('Kapon surgery completed under sterile anesthesia. Surgical incision closed.')),
                  _quickChip('URI Treated', () => _applyQuickDiagnosis('Upper respiratory symptoms treated with subQ fluids and antibiotic course.')),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _diagnosisController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter clinical diagnosis, findings, and veterinarian treatment notes...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 14),

              // 5. Prescribed Medications
              const Text(
                '4. Prescribed Medication & Directions (Optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _medicineController,
                decoration: InputDecoration(
                  hintText: 'e.g. Amoxicillin 50mg/ml - 0.5ml orally 2x daily x 7 days',
                  prefixIcon: const Icon(Icons.medication_outlined, color: AppTheme.primaryTeal, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),

              // 6. Follow-up date
              Row(
                children: [
                  const Icon(Icons.event_repeat, color: AppTheme.primaryTeal, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _followUpDate == null
                          ? 'Follow-Up Date: None scheduled'
                          : 'Follow-Up: ${DateFormat('MMM d, yyyy').format(_followUpDate!)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _followUpDate = picked);
                    },
                    child: Text(_followUpDate == null ? 'Set Date' : 'Change'),
                  ),
                  if (_followUpDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _followUpDate = null),
                    ),
                ],
              ),
              const SizedBox(height: 20),

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
                      _isSaving ? 'Syncing...' : 'Complete & Auto-Sync EMR',
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
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: AppTheme.primaryTealLight.withValues(alpha: 0.4),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}
