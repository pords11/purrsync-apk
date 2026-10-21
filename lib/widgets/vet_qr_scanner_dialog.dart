import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/cat.dart';
import '../services/firebase_service.dart';
import '../utils/app_theme.dart';
import 'clinical_emr_dialog.dart';

class VetQRScannerDialog extends StatefulWidget {
  final String providerId;
  final String providerName;

  const VetQRScannerDialog({
    super.key,
    required this.providerId,
    required this.providerName,
  });

  @override
  State<VetQRScannerDialog> createState() => _VetQRScannerDialogState();
}

class _VetQRScannerDialogState extends State<VetQRScannerDialog> {
  final FirebaseService _auth = FirebaseService();
  final TextEditingController _manualIdController = TextEditingController();
  bool _isProcessing = false;
  Map<String, dynamic>? _checkInResult;
  bool _showManualInput = false;

  @override
  void dispose() {
    _manualIdController.dispose();
    super.dispose();
  }

  Future<void> _processScannedPayload(String payload) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    String catId = payload.trim();
    try {
      if (payload.startsWith('{') && payload.endsWith('}')) {
        final map = jsonDecode(payload);
        if (map is Map && map.containsKey('catId')) {
          catId = map['catId'].toString();
        }
      }
    } catch (_) {}

    try {
      final res = await _auth.checkInPatientWithQR(
        catId: catId,
        providerId: widget.providerId,
        providerName: widget.providerName,
      );

      if (mounted) {
        setState(() {
          _checkInResult = res;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-in error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkInResult != null) {
      return _buildCheckInSuccessDialog();
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppTheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: AppTheme.primaryTeal, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Patient QR Intake Check-In',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 16),
            const Text(
              'Scan the cat\'s PurrSync QR Health Card at clinic reception to auto-check-in and assign a queue number.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),

            if (!_showManualInput) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      MobileScanner(
                        onDetect: (capture) {
                          final barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            if (barcode.rawValue != null) {
                              _processScannedPayload(barcode.rawValue!);
                              break;
                            }
                          }
                        },
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _showManualInput = true),
                icon: const Icon(Icons.keyboard, size: 16),
                label: const Text('Enter Cat ID manually / Demo mode', style: TextStyle(fontSize: 12)),
              ),
            ] else ...[
              TextField(
                controller: _manualIdController,
                decoration: InputDecoration(
                  hintText: 'Enter Cat ID or QR string',
                  prefixIcon: const Icon(Icons.tag, color: AppTheme.primaryTeal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _showManualInput = false),
                    child: const Text('Use Camera'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            final text = _manualIdController.text.trim();
                            if (text.isNotEmpty) _processScannedPayload(text);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Check In Patient', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInSuccessDialog() {
    final cat = _checkInResult!['cat'] as Cat;
    final queue = _checkInResult!['queueNumber'] as String;
    final hasAppt = _checkInResult!['hasAppointment'] as bool;
    final res = _checkInResult!['reservation'];
    final book = _checkInResult!['booking'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: AppTheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.statusSafe.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppTheme.statusSafe, size: 36),
            ),
            const SizedBox(height: 12),
            const Text(
              'Patient Checked-In!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ASSIGNED: $queue',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryTealDark),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cat: ${cat.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Breed: ${cat.breed.isNotEmpty ? cat.breed : 'Domestic'} • Gender: ${cat.genderDisplay}'),
                  Text('Age: ${cat.ageDisplay} • Weight: ${cat.weight} kg'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(hasAppt ? Icons.event_available : Icons.person_add_alt_1, size: 16, color: hasAppt ? AppTheme.statusSafe : AppTheme.statusWarning),
                      const SizedBox(width: 6),
                      Text(
                        hasAppt ? 'Scheduled Appointment Linked' : 'Walk-In / Unscheduled Triage',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: hasAppt ? AppTheme.statusSafe : AppTheme.statusWarning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
                if (hasAppt && (res != null || book != null)) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (c) => ClinicalEMRDialog(
                            appointmentId: res != null ? res.id : book!.id,
                            isBooking: book != null,
                            catId: cat.id,
                            catName: cat.name,
                            ownerId: res != null ? res.ownerId : book!.ownerId,
                            clinicName: widget.providerName,
                            initialWeight: cat.weight,
                          ),
                        );
                      },
                      icon: const Icon(Icons.medical_services_outlined, size: 16, color: Colors.white),
                      label: const Text('Start EMR', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
