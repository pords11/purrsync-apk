import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/cat.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../widgets/weight_chart.dart';
import '../widgets/boutique_animations.dart';
import '../screens/qr_health_card.dart';
import '../screens/owner/smart_triage_screen.dart';
import '../utils/app_theme.dart';
import '../utils/feline_protocol_utils.dart';


class CatDetailScreen extends StatefulWidget {
  final Cat cat;
  const CatDetailScreen({super.key, required this.cat});

  @override
  State<CatDetailScreen> createState() => _CatDetailScreenState();
}

class _CatDetailScreenState extends State<CatDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _db = FirebaseService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ============ ERROR WIDGET ============
  Widget _buildStreamError(Object? error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'Could not load records',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ============ UPDATE CAT PROFILE DIALOG ============
  void _showEditCatDialog() {
    final nameController = TextEditingController(text: widget.cat.name);
    final breedController = TextEditingController(text: widget.cat.breed);
    final weightController = TextEditingController(text: widget.cat.weight.toString());
    final formKey = GlobalKey<FormState>();

    DateTime? editBirthDate = widget.cat.birthDate;
    String? editImageBase64 = widget.cat.imageBase64;
    String? editGender = widget.cat.gender.isEmpty ? null : widget.cat.gender;
    String? dialogError;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Cat Profile'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photo picker
                  GestureDetector(
                    onTap: () async {
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
                          setDialogState(() => dialogError = 'Image must be under 700 KB.');
                          return;
                        }
                        setDialogState(() {
                          editImageBase64 = base64Encode(bytes);
                          dialogError = null;
                        });
                      } catch (e) {
                        setDialogState(() => dialogError = 'Failed to load photo: $e');
                      }
                    },
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.orange.shade100,
                          backgroundImage: (editImageBase64 != null && editImageBase64!.isNotEmpty)
                              ? MemoryImage(base64Decode(editImageBase64!))
                              : null,
                          child: (editImageBase64 == null || editImageBase64!.isEmpty)
                              ? const Icon(Icons.pets, size: 40, color: Colors.orange)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Tap to change photo', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: breedController,
                    decoration: const InputDecoration(labelText: 'Breed', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: Cat.genderOptions.contains(editGender) ? editGender : null,
                    decoration: const InputDecoration(labelText: 'Gender *', border: OutlineInputBorder()),
                    items: Cat.genderOptions
                        .map((g) => DropdownMenuItem<String>(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => editGender = val),
                    validator: (v) => (v == null || v.isEmpty) ? 'Please select a gender' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: weightController,
                    decoration: const InputDecoration(labelText: 'Weight (kg) * (0.1 - 30.0)', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final w = double.tryParse(v?.trim() ?? '');
                      if (w == null || w < 0.1 || w > 30.0) return 'Must be between 0.1 and 30 kg';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Birth Date
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      editBirthDate != null
                          ? 'Birth Date: ${editBirthDate!.toLocal().toString().split(' ')[0]}'
                          : 'Select Birth Date',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      editBirthDate != null
                          ? 'Age: ${Cat(id: '', userId: '', name: '', breed: '', weight: 0, birthDate: editBirthDate).ageDisplay}'
                          : 'Age unknown',
                      style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                    ),
                    trailing: const Icon(Icons.calendar_today, color: Colors.orange),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: editBirthDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => editBirthDate = picked);
                      }
                    },
                  ),

                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      final previousName = widget.cat.name;
                      final previousBreed = widget.cat.breed;
                      final previousWeight = widget.cat.weight;
                      final previousBirth = widget.cat.birthDate;
                      final previousPhoto = widget.cat.imageBase64;
                      final previousGender = widget.cat.gender;

                      widget.cat.name = nameController.text.trim();
                      widget.cat.breed = breedController.text.trim();
                      widget.cat.weight = double.parse(weightController.text.trim());
                      widget.cat.birthDate = editBirthDate;
                      widget.cat.gender = editGender ?? '';
                      widget.cat.imageBase64 = editImageBase64;
                      widget.cat.imageUrl = editImageBase64;

                      void rollback() {
                        widget.cat.name = previousName;
                        widget.cat.breed = previousBreed;
                        widget.cat.weight = previousWeight;
                        widget.cat.birthDate = previousBirth;
                        widget.cat.imageBase64 = previousPhoto;
                        widget.cat.gender = previousGender;
                      }

                      try {
                        await _db.updateCat(widget.cat);
                        if (context.mounted) {
                          Navigator.pop(context);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cat profile updated! ✅'), backgroundColor: Colors.green),
                          );
                        }
                      } on AppException catch (e) {
                        rollback();
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.message;
                        });
                      } catch (e) {
                        rollback();
                        setDialogState(() {
                          isSaving = false;
                          dialogError = 'Error updating profile: $e';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ============ DELETE CAT ============
  void _confirmDeleteCat() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Cat Profile'),
        content: Text('Are you sure you want to delete ${widget.cat.name}? All health logs will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.deleteCat(widget.cat.id);
                if (mounted) {
                  Navigator.pop(context); // close cat detail
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cat profile deleted')),
                  );
                }
              } on AppException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.cat.imageBase64 != null && widget.cat.imageBase64!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 248,
            pinned: true,
            backgroundColor: AppTheme.ownerAccent,
            foregroundColor: Colors.white,
            title: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: innerBoxIsScrolled ? 1.0 : 0.0,
              child: Text(
                widget.cat.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.auto_awesome, color: Colors.amber),
                tooltip: 'Smart Triage & Auto-Book',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SmartTriageScreen(initialCat: widget.cat)),
                  );
                },
              ),
              const ThemeModeToggleButton(iconColor: Colors.white),
              IconButton(
                icon: const Icon(Icons.qr_code, color: Colors.white),
                tooltip: 'QR Health Card',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => QRHealthCard(cat: widget.cat)),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                tooltip: 'Edit Profile',
                onPressed: _showEditCatDialog,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Delete Cat',
                onPressed: _confirmDeleteCat,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.tealHeaderGradient,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 44, 20, 56),
                    child: Row(
                      children: [
                        StreamBuilder<List<VaccineRecord>>(
                          stream: _db.getVaccines(widget.cat.id),
                          builder: (context, vaxSnap) {
                            CatVaccineStatus ringStatus = CatVaccineStatus.safe;
                            if (vaxSnap.hasData) {
                              final vaxList = vaxSnap.data!;
                              if (vaxList.any((v) => v.getStatus() == 'Overdue')) {
                                ringStatus = CatVaccineStatus.overdue;
                              } else if (vaxList.any((v) => v.getStatus() == 'Upcoming')) {
                                ringStatus = CatVaccineStatus.dueSoon;
                              }
                            }
                            return Hero(
                              tag: 'cat_avatar_${widget.cat.id}',
                              child: CatHealthRing(
                                status: ringStatus,
                                size: 86,
                                strokeWidth: 3.8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    image: hasImage
                                        ? DecorationImage(
                                            image: MemoryImage(base64Decode(widget.cat.imageBase64!)),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: !hasImage
                                      ? Center(
                                          child: Text(
                                            widget.cat.name.isNotEmpty ? widget.cat.name[0].toUpperCase() : '🐾',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              fontSize: 30,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.cat.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (widget.cat.breed.isNotEmpty)
                                    _buildHeaderPill(widget.cat.breed),
                                  _buildHeaderPill(widget.cat.genderDisplay),
                                  _buildHeaderPill(widget.cat.ageDisplay),
                                  _buildHeaderPill('${widget.cat.weight} kg'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.68),
              tabs: const [
                Tab(icon: Icon(Icons.vaccines_outlined), text: 'Vaccines'),
                Tab(icon: Icon(Icons.monitor_weight_outlined), text: 'Weight'),
                Tab(icon: Icon(Icons.local_hospital_outlined), text: 'Vet Visits'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildVaccinesTab(),
            _buildWeightTab(),
            _buildVetVisitsTab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        elevation: 2,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeaderPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  void _showAddDialog() {
    if (_tabController.index == 0) {
      _showAddVaccineDialog();
    } else if (_tabController.index == 1) {
      _showAddWeightDialog();
    } else {
      _showAddVetVisitDialog();
    }
  }

  // ============ VACCINES TAB ============
  Widget _buildVaccinesTab() {
    return StreamBuilder<List<VaccineRecord>>(
      stream: _db.getVaccines(widget.cat.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildStreamError(snapshot.error, () => setState(() {}));
        }
        if (!snapshot.hasData) {
          return const SkeletonCardList(itemCount: 3);
        }
        final vaccines = snapshot.data!;
        if (vaccines.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const BouncyPawEmptyState(
                    title: 'No vaccine records yet',
                    subtitle: 'Tap below to automatically generate standard AAFP feline immunization milestones, or tap + to log manually.',
                    badgeIcon: Icons.vaccines_outlined,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _autoGenerateVaccines,
                    icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                    label: const Text(
                      '⚡ Auto-Generate Core Vaccine Protocol',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: vaccines.length,
          itemBuilder: (context, index) {
            final v = vaccines[index];
            final intervalDays = v.nextDueDate.difference(v.dateGiven).inDays;
            final String displayType;
            if (v.type.toLowerCase() == 'custom') {
              displayType = 'Custom (${intervalDays}d interval)';
            } else if (v.type.toLowerCase().startsWith('custom:')) {
              final customLabel = v.type.substring(7).trim();
              displayType = '$customLabel (${intervalDays}d interval)';
            } else {
              displayType = v.type;
            }

            Color statusBg;
            Color statusText;
            final st = v.getStatus().toLowerCase();
            if (st.contains('overdue')) {
              statusBg = AppTheme.statusDangerBg;
              statusText = AppTheme.statusDanger;
            } else if (st.contains('upcoming')) {
              statusBg = AppTheme.statusWarningBg;
              statusText = AppTheme.statusWarning;
            } else {
              statusBg = AppTheme.statusSafeBg;
              statusText = AppTheme.statusSafe;
            }

            return FadeInSlide(
              key: ValueKey('vax_${v.id}'),
              delay: Duration(milliseconds: 35 * index),
              duration: const Duration(milliseconds: 340),
              child: Dismissible(
                key: ValueKey('dismiss_vax_${v.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: AppTheme.statusDanger,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Delete',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                onDismissed: (_) async {
                  await NotificationService.cancelReminder(v.id);
                  await _db.deleteVaccineRecord(v.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Deleted $displayType record'),
                        action: SnackBarAction(
                          label: 'UNDO',
                          textColor: Colors.amberAccent,
                          onPressed: () async {
                            final restoredId = await _db.addVaccine(v);
                            await NotificationService.scheduleVaccineReminder(
                              restoredId,
                              widget.cat.name,
                              v.nextDueDate,
                            );
                          },
                        ),
                      ),
                    );
                  }
                },
                child: BouncingScale(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.dividerFor(context)),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.vaccines, color: statusText, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        displayType,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimaryColor(context)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusBg,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        v.getStatus(),
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: statusText),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Given: ${v.dateGiven.toLocal().toString().split(' ')[0]}  •  Next: ${v.nextDueDate.toLocal().toString().split(' ')[0]}',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor(context), fontWeight: FontWeight.w500),
                                ),
                                if ((v.clinicName != null && v.clinicName!.isNotEmpty) || (v.veterinarian != null && v.veterinarian!.isNotEmpty)) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    '${v.clinicName != null ? 'Clinic: ${v.clinicName} ' : ''}${v.veterinarian != null ? '• Vet: ${v.veterinarian}' : ''}',
                                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textTertiary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textTertiary),
                            onSelected: (val) {
                              if (val == 'delete') {
                                _confirmDeleteVaccine(v);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete')])),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _autoGenerateVaccines() async {
    final records = FelineProtocolUtils.generateProtocolForCat(widget.cat);
    try {
      for (final v in records) {
        await _db.addVaccine(v);
      }
      if (mounted) {
        showPurrSyncSuccessOverlay(
          context,
          title: 'Protocol Generated!',
          subtitle: 'Core feline vaccine milestones have been scheduled.',
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating protocol: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDeleteVaccine(VaccineRecord record) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Vaccine Record'),
        content: Text('Delete ${record.type} record given on ${record.dateGiven.toLocal().toString().split(' ')[0]}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await NotificationService.cancelReminder(record.id);
                await _db.deleteVaccineRecord(record.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vaccine record deleted')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddVaccineDialog() {
    String selectedType = 'Anti-rabies';
    final clinicCtrl = TextEditingController();
    final vetCtrl = TextEditingController();
    final customNameCtrl = TextEditingController();
    final customIntervalCtrl = TextEditingController(text: '30');
    DateTime dateGiven = DateTime.now();
    String? dialogError;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Vaccine Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Vaccine Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Anti-rabies', child: Text('Anti-rabies')),
                    DropdownMenuItem(value: '4-in-1', child: Text('4-in-1')),
                    DropdownMenuItem(value: 'Deworming', child: Text('Deworming')),
                    DropdownMenuItem(value: 'Custom', child: Text('Custom Interval')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedType = val;
                        dialogError = null;
                      });
                    }
                  },
                ),
                if (selectedType == 'Custom') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: customNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Specify Custom Details / Name *',
                      hintText: 'e.g., 4-in-1 Booster, FeLV Vaccine',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: customIntervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom interval (days until next due) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: clinicCtrl,
                  decoration: const InputDecoration(labelText: 'Clinic Name (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: vetCtrl,
                  decoration: const InputDecoration(labelText: 'Veterinarian (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: const Text('Date Given'),
                  subtitle: Text(dateGiven.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dateGiven,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        dateGiven = picked;
                        if (!VaccineRecord.isValidGivenDate(picked, widget.cat.birthDate)) {
                          dialogError = "Vaccine date cannot be before the cat's birthdate.";
                        } else {
                          dialogError = null;
                        }
                      });
                    }
                  },
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      if (!VaccineRecord.isValidGivenDate(dateGiven, widget.cat.birthDate)) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = "Vaccine date cannot be before the cat's birthdate.";
                        });
                        return;
                      }

                      int? customDays;
                      String resolvedType = selectedType;
                      if (selectedType == 'Custom') {
                        if (customNameCtrl.text.trim().isEmpty) {
                          setDialogState(() {
                            isSaving = false;
                            dialogError = 'Please specify the custom vaccine / treatment name.';
                          });
                          return;
                        }
                        customDays = int.tryParse(customIntervalCtrl.text.trim());
                        if (customDays == null || customDays <= 0) {
                          setDialogState(() {
                            isSaving = false;
                            dialogError = 'Custom interval must be a whole number greater than 0.';
                          });
                          return;
                        }
                        resolvedType = 'Custom: ${customNameCtrl.text.trim()}';
                      }

                      // Check duplicate before saving
                      final isDup = await _db.hasDuplicateVaccineOnDate(widget.cat.id, resolvedType, dateGiven);
                      if (isDup) {
                        final ymd = dateGiven.toLocal().toString().split(' ')[0];
                        setDialogState(() {
                          isSaving = false;
                          dialogError = 'A $resolvedType record already exists for $ymd. Pick a different date or edit the existing record instead.';
                        });
                        return;
                      }

                      final nextDue = VaccineRecord.calculateNextDue(
                        selectedType,
                        dateGiven,
                        customIntervalDays: customDays,
                      );

                      final vaccine = VaccineRecord(
                        id: '',
                        catId: widget.cat.id,
                        type: resolvedType,
                        dateGiven: dateGiven,
                        nextDueDate: nextDue,
                        clinicName: clinicCtrl.text.trim().isNotEmpty ? clinicCtrl.text.trim() : null,
                        veterinarian: vetCtrl.text.trim().isNotEmpty ? vetCtrl.text.trim() : null,
                      );

                      try {
                        final vaccineId = await _db.addVaccine(vaccine);
                        await NotificationService.scheduleVaccineReminder(vaccineId, widget.cat.name, nextDue);
                        if (context.mounted) {
                          Navigator.pop(context);
                          await showPurrSyncSuccessOverlay(
                            context,
                            title: 'Vaccine Saved!',
                            subtitle: 'Next booster due ${nextDue.toLocal().toString().split(' ')[0]}',
                          );
                        }
                      } on AppException catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.message;
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = 'Error: $e';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ============ WEIGHT TAB ============
  Widget _buildWeightTab() {
    return Column(
      children: [
        FadeInSlide(
          duration: const Duration(milliseconds: 500),
          direction: AxisDirection.down,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
                boxShadow: AppTheme.cardShadow,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: WeightChart(catId: widget.cat.id),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<WeightLog>>(
            stream: _db.getWeightLogs(widget.cat.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildStreamError(snapshot.error, () => setState(() {}));
              }
              if (!snapshot.hasData) {
                return const SkeletonCardList(itemCount: 3);
              }
              final logs = snapshot.data!;
              if (logs.isEmpty) {
                return const BouncyPawEmptyState(
                  title: 'No weight records yet',
                  subtitle: 'Tap + to log your cat\'s current weight and visualize trends.',
                  badgeIcon: Icons.monitor_weight_outlined,
                );
              }
              final anomaly = FelineProtocolUtils.detectWeightAnomaly(logs, widget.cat.weight);

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: logs.length + (anomaly.detected ? 1 : 0),
                itemBuilder: (context, index) {
                  if (anomaly.detected && index == 0) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.statusDanger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.statusDanger, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppTheme.statusDanger, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  anomaly.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.statusDanger),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            anomaly.recommendation,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => SmartTriageScreen(initialCat: widget.cat)),
                                );
                              },
                              icon: const Icon(Icons.flash_on, size: 15, color: Colors.white),
                              label: const Text('Auto-Match Diagnostic Vet Now', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.statusDanger,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final logIndex = anomaly.detected ? index - 1 : index;
                  final log = logs[logIndex];
                  return FadeInSlide(
                    key: ValueKey('weight_${log.id}'),
                    delay: Duration(milliseconds: 35 * index),
                    duration: const Duration(milliseconds: 340),
                    child: Dismissible(
                      key: ValueKey('dismiss_weight_${log.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: AppTheme.statusDanger,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      onDismissed: (_) async {
                        await _db.deleteWeightLog(log.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Deleted ${log.weight} kg weight log'),
                              action: SnackBarAction(
                                label: 'UNDO',
                                textColor: Colors.amberAccent,
                                onPressed: () => _db.addWeightLog(log),
                              ),
                            ),
                          );
                        }
                      },
                      child: BouncingScale(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface(context),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppTheme.dividerFor(context)),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.terracottaLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.monitor_weight_outlined, color: AppTheme.terracotta, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${log.weight} kg',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimaryColor(context)),
                                          ),
                                          if (log.notes != null && log.notes!.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.surfaceMuted,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                log.notes!,
                                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        log.date.toLocal().toString().split(' ')[0],
                                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor(context)),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textTertiary),
                                  onSelected: (val) {
                                    if (val == 'delete') {
                                      _confirmDeleteWeightLog(log);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete')])),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmDeleteWeightLog(WeightLog log) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Weight Log'),
        content: Text('Delete weight record of ${log.weight} kg on ${log.date.toLocal().toString().split(' ')[0]}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.deleteWeightLog(log.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Weight log deleted')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddWeightDialog() {
    final weightCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime logDate = DateTime.now();
    String? dialogError;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Cat Weight'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: weightCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg) * (0.1 - 30.0)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(logDate.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today, color: Colors.orange),
                  onTap: () async {
                    final earliest = widget.cat.birthDate ?? DateTime(2015);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: logDate.isBefore(earliest) ? earliest : logDate,
                      firstDate: earliest,
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        logDate = picked;
                        if (widget.cat.birthDate != null &&
                            picked.isBefore(DateTime(
                              widget.cat.birthDate!.year,
                              widget.cat.birthDate!.month,
                              widget.cat.birthDate!.day,
                            ))) {
                          dialogError = "Weight log date cannot be before the cat's birthdate.";
                        } else {
                          dialogError = null;
                        }
                      });
                    }
                  },
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              onPressed: isSaving
                  ? null
                  : () async {
                      final w = double.tryParse(weightCtrl.text.trim());
                      if (w == null || w < 0.1 || w > 30.0) {
                        setDialogState(() => dialogError = 'Please enter a weight between 0.1 and 30 kg.');
                        return;
                      }

                      if (widget.cat.birthDate != null &&
                          logDate.isBefore(DateTime(
                            widget.cat.birthDate!.year,
                            widget.cat.birthDate!.month,
                            widget.cat.birthDate!.day,
                          ))) {
                        setDialogState(() => dialogError = "Weight log date cannot be before the cat's birthdate.");
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      final log = WeightLog(
                        id: '',
                        catId: widget.cat.id,
                        weight: w,
                        date: logDate,
                        notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                      );

                      try {
                        await _db.addWeightLog(log);
                        widget.cat.weight = w;
                        await _db.updateCat(widget.cat);
                        if (context.mounted) {
                          Navigator.pop(context);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Weight logged! ⚖️'), backgroundColor: Colors.green),
                          );
                        }
                      } on AppException catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.message;
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = 'Error: $e';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ============ VET VISITS TAB ============
  Widget _buildVetVisitsTab() {
    return StreamBuilder<List<VetVisit>>(
      stream: _db.getVetVisits(widget.cat.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildStreamError(snapshot.error, () => setState(() {}));
        }
        if (!snapshot.hasData) {
          return const SkeletonCardList(itemCount: 3);
        }
        final visits = snapshot.data!;
        if (visits.isEmpty) {
          return const BouncyPawEmptyState(
            title: 'No vet visits recorded yet',
            subtitle: 'Tap + to log clinical checkups, diagnoses, or prescribed treatments.',
            badgeIcon: Icons.local_hospital_outlined,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: visits.length,
          itemBuilder: (context, index) {
            final v = visits[index];
            return FadeInSlide(
              key: ValueKey('visit_${v.id}'),
              delay: Duration(milliseconds: 35 * index),
              duration: const Duration(milliseconds: 340),
              child: Dismissible(
                key: ValueKey('dismiss_visit_${v.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: AppTheme.statusDanger,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                onDismissed: (_) async {
                  await _db.deleteVetVisit(v.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Deleted visit at ${v.clinicName}'),
                        action: SnackBarAction(
                          label: 'UNDO',
                          textColor: Colors.amberAccent,
                          onPressed: () => _db.addVetVisit(v),
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.dividerFor(context)),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTealLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.local_hospital_outlined, color: AppTheme.primaryTeal, size: 22),
                      ),
                      title: Text(
                        v.clinicName,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimaryColor(context)),
                      ),
                      subtitle: Text(
                        'Visited: ${v.visitDate.toLocal().toString().split(' ')[0]}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor(context)),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textTertiary),
                        onSelected: (val) {
                          if (val == 'delete') {
                            _confirmDeleteVetVisit(v);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete')])),
                        ],
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppTheme.scaffoldBg(context),
                            border: Border(top: BorderSide(color: AppTheme.dividerFor(context))),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Text('Reason: ${v.reason}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimaryColor(context))),
                              const SizedBox(height: 4),
                              Text('Diagnosis: ${v.diagnosis}', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor(context))),
                              if (v.prescribedMedicine != null && v.prescribedMedicine!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Medicine: ${v.prescribedMedicine}', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondaryColor(context))),
                              ],
                              if (v.followUpDate != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.terracottaLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Follow-up: ${v.followUpDate!.toLocal().toString().split(' ')[0]}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.terracotta),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteVetVisit(VetVisit visit) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Vet Visit'),
        content: Text('Delete visit record for ${visit.clinicName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _db.deleteVetVisit(visit.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visit record deleted')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddVetVisitDialog() {
    final clinicCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final diagnosisCtrl = TextEditingController();
    final medicineCtrl = TextEditingController();
    DateTime visitDate = DateTime.now();
    DateTime? followUpDate;
    String? dialogError;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Vet Visit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: clinicCtrl,
                  decoration: const InputDecoration(labelText: 'Clinic Name *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Reason for Visit *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: diagnosisCtrl,
                  decoration: const InputDecoration(labelText: 'Diagnosis *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: medicineCtrl,
                  decoration: const InputDecoration(labelText: 'Prescribed Medicine (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: const Text('Visit Date'),
                  subtitle: Text(visitDate.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today, color: Colors.orange),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: visitDate,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        visitDate = picked;
                        if (widget.cat.birthDate != null && picked.isBefore(DateTime(widget.cat.birthDate!.year, widget.cat.birthDate!.month, widget.cat.birthDate!.day))) {
                          dialogError = "Visit date cannot be before the cat's birthdate.";
                        } else {
                          dialogError = null;
                        }
                      });
                    }
                  },
                ),
                ListTile(
                  title: const Text('Follow-up Date (optional)'),
                  subtitle: Text(followUpDate != null ? followUpDate!.toLocal().toString().split(' ')[0] : 'None set'),
                  trailing: const Icon(Icons.event, color: Colors.orange),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => followUpDate = picked);
                    }
                  },
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (clinicCtrl.text.trim().isEmpty || reasonCtrl.text.trim().isEmpty || diagnosisCtrl.text.trim().isEmpty) {
                        setDialogState(() => dialogError = 'Clinic name, reason, and diagnosis are required.');
                        return;
                      }

                      if (widget.cat.birthDate != null && visitDate.isBefore(DateTime(widget.cat.birthDate!.year, widget.cat.birthDate!.month, widget.cat.birthDate!.day))) {
                        setDialogState(() => dialogError = "Visit date cannot be before the cat's birthdate.");
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      final visit = VetVisit(
                        id: '',
                        catId: widget.cat.id,
                        visitDate: visitDate,
                        clinicName: clinicCtrl.text.trim(),
                        reason: reasonCtrl.text.trim(),
                        diagnosis: diagnosisCtrl.text.trim(),
                        prescribedMedicine: medicineCtrl.text.trim().isNotEmpty ? medicineCtrl.text.trim() : null,
                        followUpDate: followUpDate,
                      );

                      try {
                        await _db.addVetVisit(visit);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Vet visit logged! 🏥'), backgroundColor: Colors.green),
                          );
                        }
                      } on AppException catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = e.message;
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          dialogError = 'Error: $e';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}