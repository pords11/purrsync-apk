import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapUtils {
  /// Opens Google Maps with direct navigation/directions to the destination address.
  static Future<void> openDirections({
    required String destinationAddress,
    String? clinicName,
    BuildContext? context,
  }) async {
    final cleanQuery = [
      if (clinicName != null && clinicName.trim().isNotEmpty) clinicName.trim(),
      destinationAddress.trim(),
    ].join(', ');

    // 1. Google Maps Directions Universal URL
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(cleanQuery)}',
    );

    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        // Fallback to web browser or generic maps search
        final searchUrl = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(cleanQuery)}',
        );
        await launchUrl(searchUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Opens Google Maps search centered on the clinic location.
  static Future<void> openSearch({
    required String address,
    String? clinicName,
    BuildContext? context,
  }) async {
    final cleanQuery = [
      if (clinicName != null && clinicName.trim().isNotEmpty) clinicName.trim(),
      address.trim(),
    ].join(', ');

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(cleanQuery)}',
    );

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}
