import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/cat.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';
import '../widgets/boutique_animations.dart';


class AddCatScreen extends StatefulWidget {
  const AddCatScreen({super.key});

  @override
  State<AddCatScreen> createState() => _AddCatScreenState();
}

class _AddCatScreenState extends State<AddCatScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _dietNotesController = TextEditingController();
  final TextEditingController _customIntervalController = TextEditingController(text: '30');
  final TextEditingController _customVaccineNameController = TextEditingController();

  // Gender state (required)
  String? _gender;

  // Photo state
  String? _imageBase64;
  String? _photoError;

  // Birth Date state
  DateTime? _birthDate;

  // Vaccine state
  bool _includeInitialVaccine = false;
  String _vaccineType = 'Anti-Rabies (1 Year)';
  DateTime? _vaccineDateGiven;
  DateTime? _nextVaccineDate;

  bool _isLoading = false;

  Future<void> _pickPhoto() async {
    setState(() => _photoError = null);
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > 700 * 1024) {
        setState(() => _photoError = 'Image must be under 700 KB. Please pick a smaller image.');
        return;
      }

      setState(() {
        _imageBase64 = base64Encode(bytes);
      });
    } catch (e) {
      setState(() => _photoError = 'Could not load image: $e');
    }
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        if (_vaccineDateGiven != null && _vaccineDateGiven!.isBefore(picked)) {
          _vaccineDateGiven = null;
          _nextVaccineDate = null;
        }
      });
    }
  }

  void _calculateNextVaccine() {
    if (_vaccineDateGiven == null) return;
    int? customDays;
    if (_vaccineType == 'Custom') {
      customDays = int.tryParse(_customIntervalController.text.trim()) ?? 30;
    }
    setState(() {
      _nextVaccineDate = VaccineRecord.calculateNextDue(
        _vaccineType,
        _vaccineDateGiven!,
        customIntervalDays: customDays,
      );
    });
  }

  Future<void> _pickVaccineDate() async {
    final earliest = _birthDate ?? DateTime(2015);
    final initial = _vaccineDateGiven ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(earliest) ? earliest : initial,
      firstDate: earliest,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _vaccineDateGiven = picked);
      _calculateNextVaccine();
    }
  }

  Future<void> _saveCat() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _firebaseService.getCurrentUser();
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to add a cat'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_includeInitialVaccine) {
      if (_vaccineDateGiven == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select the date given for the vaccine'), backgroundColor: Colors.red),
        );
        return;
      }
      if (!VaccineRecord.isValidGivenDate(_vaccineDateGiven!, _birthDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vaccine date cannot be before the cat's birthdate."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final weight = double.parse(_weightController.text.trim());
      final cat = Cat(
        id: '',
        userId: user.uid,
        name: _nameController.text.trim(),
        breed: _breedController.text.trim(),
        weight: weight,
        birthDate: _birthDate,
        gender: _gender ?? '',
        imageBase64: _imageBase64,
        imageUrl: _imageBase64,
      );

      // Save cat via FirebaseService
      final catId = await _firebaseService.addCat(cat);

      // Save initial weight log
      await _firebaseService.addWeightLog(
        WeightLog(
          id: '',
          catId: catId,
          weight: weight,
          date: DateTime.now(),
          notes: 'Initial weight log',
        ),
      );

      // If initial vaccine provided, save as real VaccineRecord document
      if (_includeInitialVaccine && _vaccineDateGiven != null && _nextVaccineDate != null) {
        String cleanType = _vaccineType;
        if (_vaccineType.contains('Anti-Rabies')) cleanType = 'Anti-rabies';
        if (_vaccineType.contains('4-in-1')) cleanType = '4-in-1';
        if (_vaccineType.contains('Deworming')) cleanType = 'Deworming';
        if (_vaccineType == 'Custom') {
          cleanType = 'Custom: ${_customVaccineNameController.text.trim()}';
        }

        final vRecord = VaccineRecord(
          id: '',
          catId: catId,
          type: cleanType,
          dateGiven: _vaccineDateGiven!,
          nextDueDate: _nextVaccineDate!,
          notes: _dietNotesController.text.trim().isNotEmpty ? _dietNotesController.text.trim() : null,
        );

        final vaccineId = await _firebaseService.addVaccine(vRecord);
        await NotificationService.scheduleVaccineReminder(vaccineId, cat.name, _nextVaccineDate!);
      }

      if (mounted) {
        await showPurrSyncSuccessOverlay(
          context,
          title: 'Cat Profile Saved!',
          subtitle: '${cat.name} is now registered in PurrSync.',
        );
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _dietNotesController.dispose();
    _customIntervalController.dispose();
    _customVaccineNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Preview age string
    final previewCat = Cat(
      id: '',
      userId: '',
      name: '',
      breed: '',
      weight: 0,
      birthDate: _birthDate,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Cat Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Photo avatar
                    GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 54,
                            backgroundColor: AppTheme.primaryTealLight,
                            backgroundImage: _imageBase64 != null
                                ? MemoryImage(base64Decode(_imageBase64!))
                                : null,
                            child: _imageBase64 == null
                                ? const Icon(Icons.pets, size: 54, color: AppTheme.primaryTeal)
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryTeal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _imageBase64 == null ? 'Tap to add cat photo' : 'Tap to change photo',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    if (_photoError != null) ...[
                      const SizedBox(height: 4),
                      Text(_photoError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                    const SizedBox(height: 20),

                    // Cat name
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: "Cat's Name *",
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                    ),
                    const SizedBox(height: 16),

                    // Breed
                    TextFormField(
                      controller: _breedController,
                      decoration: InputDecoration(
                        labelText: 'Breed (optional, e.g. Persian, Siamese)',
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Gender (required)
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: InputDecoration(
                        labelText: 'Gender *',
                        prefixIcon: const Icon(Icons.transgender, color: AppTheme.primaryTeal),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      items: Cat.genderOptions
                          .map((g) => DropdownMenuItem<String>(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (val) => setState(() => _gender = val),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please select a gender' : null,
                    ),
                    const SizedBox(height: 16),

                    // Weight
                    TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Weight (kg) * (0.1 - 30.0)',
                        prefixIcon: const Icon(Icons.monitor_weight_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter weight';
                        final w = double.tryParse(v.trim());
                        if (w == null || w < 0.1 || w > 30.0) {
                          return 'Weight must be between 0.1 and 30.0 kg';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Birth date picker
                    InkWell(
                      onTap: _pickBirthDate,
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Birth Date (for age calculation)',
                          prefixIcon: const Icon(Icons.cake_outlined, color: AppTheme.primaryTeal),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          suffixIcon: _birthDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() => _birthDate = null),
                                )
                              : null,
                        ),
                        child: Text(
                          _birthDate != null
                              ? '${_birthDate!.toLocal().toString().split(' ')[0]}  (Age: ${previewCat.ageDisplay})'
                              : 'Select Birth Date (optional)',
                          style: TextStyle(
                            color: _birthDate != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Initial Vaccine Toggle
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppTheme.borderLight),
                      ),
                      color: AppTheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Record Initial Vaccine / Deworming',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                              ),
                              value: _includeInitialVaccine,
                              activeThumbColor: AppTheme.primaryTeal,
                              onChanged: (val) => setState(() => _includeInitialVaccine = val),
                            ),
                            if (_includeInitialVaccine) ...[
                              const Divider(),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _vaccineType,
                                decoration: InputDecoration(
                                  labelText: 'Vaccine / Treatment Type',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Anti-Rabies (1 Year)',
                                    child: Text('Anti-Rabies (1 Year)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '4-in-1 (1 Year)',
                                    child: Text('4-in-1 (1 Year)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Deworming (3 Months)',
                                    child: Text('Deworming (3 Months)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Custom',
                                    child: Text('Custom Interval'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _vaccineType = val);
                                    _calculateNextVaccine();
                                  }
                                },
                              ),
                              if (_vaccineType == 'Custom') ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _customVaccineNameController,
                                  decoration: InputDecoration(
                                    labelText: 'Specify Custom Details / Name *',
                                    hintText: 'e.g., 4-in-1 Booster, FeLV Vaccine',
                                    prefixIcon: const Icon(Icons.edit_note, color: AppTheme.primaryTeal),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  validator: (v) {
                                    if (!_includeInitialVaccine || _vaccineType != 'Custom') return null;
                                    if (v == null || v.trim().isEmpty) return 'Please specify the vaccine / treatment name';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _customIntervalController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Custom interval (days until next due) *',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  validator: (v) {
                                    if (!_includeInitialVaccine || _vaccineType != 'Custom') return null;
                                    final n = int.tryParse(v?.trim() ?? '');
                                    if (n == null || n <= 0) return 'Must be a whole number greater than 0';
                                    return null;
                                  },
                                  onChanged: (_) => _calculateNextVaccine(),
                                ),
                              ],
                              const SizedBox(height: 12),
                              ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: AppTheme.borderLight),
                                ),
                                title: Text(
                                  _vaccineDateGiven == null
                                      ? 'Select Date Given'
                                      : 'Date Given: ${_vaccineDateGiven!.toLocal().toString().split(' ')[0]}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  _nextVaccineDate == null
                                      ? 'Next due date auto-computes'
                                      : 'Next Due: ${_nextVaccineDate!.toLocal().toString().split(' ')[0]}',
                                  style: TextStyle(
                                    color: _nextVaccineDate != null ? AppTheme.terracotta : AppTheme.textSecondary,
                                    fontWeight: _nextVaccineDate != null ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                trailing: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal),
                                tileColor: AppTheme.surface,
                                onTap: _pickVaccineDate,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Nutrition Info
                    TextFormField(
                      controller: _dietNotesController,
                      decoration: InputDecoration(
                        labelText: 'Diet / Nutrition Notes (optional, e.g. Royal Canin)',
                        prefixIcon: const Icon(Icons.restaurant_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isLoading ? null : _saveCat,
                        child: const Text(
                          'Save Profile',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}