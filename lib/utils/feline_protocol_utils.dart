import '../models/cat.dart';

class WeightAnomaly {
  final bool detected;
  final double percentageChange;
  final String title;
  final String recommendation;
  final bool isSevere;

  const WeightAnomaly({
    required this.detected,
    this.percentageChange = 0.0,
    this.title = '',
    this.recommendation = '',
    this.isSevere = false,
  });
}

class FelineProtocolUtils {
  /// Analyzes recent weight records to detect rapid, dangerous feline weight loss (>10% drop in <60 days).
  static WeightAnomaly detectWeightAnomaly(List<WeightLog> logs, double currentWeight) {
    if (logs.length < 2) return const WeightAnomaly(detected: false);

    final sorted = List<WeightLog>.from(logs)..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();

    // Look for records within the past 60 days
    final recentLogs = sorted.where((l) => now.difference(l.date).inDays <= 60).toList();
    if (recentLogs.length < 2) return const WeightAnomaly(detected: false);

    final latest = recentLogs.first.weight;
    final baseline = recentLogs.last.weight;

    if (baseline <= 0) return const WeightAnomaly(detected: false);

    final percentChange = ((latest - baseline) / baseline) * 100.0;

    // Weight drop > 10% in cats is a primary clinical warning sign for CKD, Diabetes, or Hepatic Lipidosis
    if (percentChange <= -10.0) {
      return WeightAnomaly(
        detected: true,
        percentageChange: percentChange,
        title: '⚠️ Rapid Weight Loss Warning (${percentChange.toStringAsFixed(1)}%)',
        recommendation:
            'A weight loss of more than 10% within 60 days can trigger feline hepatic lipidosis (fatty liver). Immediate veterinary diagnostic evaluation is recommended.',
        isSevere: percentChange <= -15.0,
      );
    }

    return const WeightAnomaly(detected: false);
  }

  /// Automatically generates standard core feline vaccination and health milestone protocols
  /// based on the cat's birthdate or current age.
  static List<VaccineRecord> generateProtocolForCat(Cat cat) {
    final now = DateTime.now();
    final isKitten = cat.birthDate != null && now.difference(cat.birthDate!).inDays < 365;

    final List<VaccineRecord> generated = [];

    if (isKitten) {
      final bDate = cat.birthDate!;
      // Dose 1: ~8 weeks (56 days)
      final dose1Date = bDate.add(const Duration(days: 56));
      generated.add(VaccineRecord(
        id: '',
        catId: cat.id,
        type: '4-in-1 FVRCP Core (Dose 1)',
        dateGiven: dose1Date.isBefore(now) ? dose1Date : now,
        nextDueDate: dose1Date.add(const Duration(days: 28)), // 4 weeks later
        notes: 'Initial core immunization for feline viral rhinotracheitis, calicivirus, and panleukopenia.',
      ));

      // Dose 2: ~12 weeks (84 days)
      final dose2Date = bDate.add(const Duration(days: 84));
      generated.add(VaccineRecord(
        id: '',
        catId: cat.id,
        type: '4-in-1 FVRCP Core (Dose 2 Booster)',
        dateGiven: dose2Date.isBefore(now) ? dose2Date : now.add(const Duration(days: 28)),
        nextDueDate: dose2Date.add(const Duration(days: 28)),
        notes: 'Second kitten booster to overcome maternal antibody interference.',
      ));

      // Dose 3 + Rabies: ~16 weeks (112 days)
      final dose3Date = bDate.add(const Duration(days: 112));
      generated.add(VaccineRecord(
        id: '',
        catId: cat.id,
        type: 'Anti-Rabies Core Vaccine (Kitten Shot)',
        dateGiven: dose3Date.isBefore(now) ? dose3Date : now.add(const Duration(days: 56)),
        nextDueDate: dose3Date.add(const Duration(days: 365)), // 1 year
        notes: 'Mandatory anti-rabies vaccination; valid for 1 year.',
      ));
    } else {
      // Adult Core Schedule
      generated.add(VaccineRecord(
        id: '',
        catId: cat.id,
        type: '4-in-1 FVRCP Core Annual Booster',
        dateGiven: now,
        nextDueDate: now.add(const Duration(days: 365)),
        notes: 'Annual adult core feline booster protecting against respiratory and panleukopenia viruses.',
      ));

      generated.add(VaccineRecord(
        id: '',
        catId: cat.id,
        type: 'Anti-Rabies 1-Year Booster',
        dateGiven: now,
        nextDueDate: now.add(const Duration(days: 365)),
        notes: 'Standard annual rabies immunization for adult felines.',
      ));

      generated.add(VaccineRecord(
        id: '',
        catId: cat.id,
        type: 'Broad-Spectrum Deworming',
        dateGiven: now,
        nextDueDate: now.add(const Duration(days: 90)), // 3 months
        notes: 'Quarterly internal parasite prevention (roundworms, tapeworms, hookworms).',
      ));
    }

    return generated;
  }
}
