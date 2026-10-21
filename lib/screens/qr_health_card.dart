import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/cat.dart';
import '../utils/app_theme.dart';

class QRHealthCard extends StatelessWidget {
  final Cat cat;
  const QRHealthCard({super.key, required this.cat});

  @override
  Widget build(BuildContext context) {
    final qrData = jsonEncode({
      'purrsync': true,
      'catId': cat.id,
      'userId': cat.userId,
      'name': cat.name,
      'breed': cat.breed,
      'gender': cat.genderDisplay,
      'weight': cat.weight,
      'age': cat.ageDisplay,
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('${cat.name}\'s Health Card', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: AppTheme.primaryTealLight,
                backgroundImage: (cat.imageBase64 != null && cat.imageBase64!.isNotEmpty)
                    ? MemoryImage(base64Decode(cat.imageBase64!))
                    : null,
                child: (cat.imageBase64 == null || cat.imageBase64!.isEmpty)
                    ? Text(
                        cat.name.isNotEmpty ? cat.name[0].toUpperCase() : '🐾',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.primaryTealDark),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                cat.name,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                '${cat.breed.isNotEmpty ? '${cat.breed} • ' : ''}${cat.genderDisplay} • ${cat.ageDisplay} • ${cat.weight} kg',
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                color: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTheme.borderLight),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 16, color: AppTheme.primaryTeal),
                    SizedBox(width: 6),
                    Text(
                      'Ready for Clinic Kiosk & Intake Check-In',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
