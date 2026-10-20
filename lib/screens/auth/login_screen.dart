import 'package:flutter/material.dart';
import '../../models/user_role.dart';
import '../../models/provider_profile.dart';
import '../../services/firebase_service.dart';
import '../../widgets/operating_hours_selector.dart';
import '../../widgets/boutique_animations.dart';
import '../../utils/app_theme.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseService _auth = FirebaseService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Registration controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _specialtyController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  // Clock dial operating hours state
  String _openTime = '08:00';
  String _closeTime = '18:00';
  List<int> _openDays = [1, 2, 3, 4, 5, 6];

  bool _showPortalWelcome = true;
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  UserRole _selectedRole = UserRole.owner;

  @override
  void initState() {
    super.initState();
    if (FirebaseService.selectedPortalRole != null) {
      _selectedRole = FirebaseService.selectedPortalRole!;
    } else {
      FirebaseService.selectedPortalRole = _selectedRole;
    }
    if (FirebaseService.pendingPortalError != null) {
      _errorMessage = FirebaseService.pendingPortalError;
      _showPortalWelcome = false;
      FirebaseService.pendingPortalError = null;
    }
  }

  void _selectPortalRole(UserRole role) {
    setState(() {
      _selectedRole = role;
      _errorMessage = null;
      FirebaseService.selectedPortalRole = role;
      FirebaseService.pendingPortalError = null;
    });
  }

  final List<String> _availableVisitTypes = const [
    'Checkup',
    'Vaccination',
    'Consultation',
    'Follow-up',
    'Emergency',
    'Other',
  ];
  final Set<String> _selectedVisitTypes = {'Checkup', 'Vaccination', 'Consultation'};

  final RegExp _emailRegex = RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$');

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  ProviderProfile? _validateAndBuildProviderProfile() {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Clinic or Veterinarian Name is required');
      return null;
    }
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Clinic Phone number is required');
      return null;
    }
    if (_cityController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'City is required');
      return null;
    }
    if (_addressController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Clinic Address is required');
      return null;
    }
    if (_openDays.isEmpty) {
      setState(() => _errorMessage = 'Please select at least one open day');
      return null;
    }
    final openH = int.parse(_openTime.split(':')[0]);
    final openM = int.parse(_openTime.split(':')[1]);
    final closeH = int.parse(_closeTime.split(':')[0]);
    final closeM = int.parse(_closeTime.split(':')[1]);
    if ((closeH * 60 + closeM) <= (openH * 60 + openM)) {
      setState(() => _errorMessage = 'Closing time must be after opening time');
      return null;
    }
    if (_selectedVisitTypes.isEmpty) {
      setState(() => _errorMessage = 'Please select at least one visit type handled');
      return null;
    }

    final fullName = _nameController.text.trim();
    return ProviderProfile(
      id: '',
      role: _selectedRole,
      displayName: fullName,
      address: _addressController.text.trim(),
      city: _cityController.text.trim(),
      phone: _phoneController.text.trim(),
      bio: _bioController.text.trim(),
      specialty: _specialtyController.text.trim().isNotEmpty
          ? _specialtyController.text.trim()
          : null,
      visitTypes: _selectedVisitTypes.toList(),
      openTime: _openTime,
      closeTime: _closeTime,
      openDays: _openDays,
      hoursLabel: ProviderProfile.computeHoursLabel(_openDays, _openTime, _closeTime),
      active: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    ProviderProfile? providerProfile;
    if (!_isLogin && _selectedRole.isProvider) {
      providerProfile = _validateAndBuildProviderProfile();
      if (providerProfile == null) return;
    }

    setState(() => _isLoading = true);
    FirebaseService.selectedPortalRole = _selectedRole;

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isLogin) {
        await _auth.signIn(
          email,
          password,
          expectedRole: _selectedRole,
        );
      } else {
        final fullName = _nameController.text.trim();
        await _auth.signUp(
          email,
          password,
          fullName,
          role: _selectedRole,
          providerProfile: providerProfile,
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Something went wrong: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _errorMessage = null);

    ProviderProfile? providerProfile;
    if (!_isLogin && _selectedRole.isProvider) {
      providerProfile = _validateAndBuildProviderProfile();
      if (providerProfile == null) return;
    }

    setState(() => _isLoading = true);
    FirebaseService.selectedPortalRole = _selectedRole;

    try {
      await _auth.signInWithGoogle(
        expectedRole: _selectedRole,
        isLoginMode: _isLogin,
        providerProfile: providerProfile,
        customFullName: !_isLogin ? _nameController.text.trim() : null,
      );
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Google sign-in error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildPortalOptionCard({
    required bool isSelected,
    required String title,
    required String description,
    required String badgeText,
    required IconData icon,
    required Color circleColor,
    required VoidCallback onTap,
  }) {
    return BouncingScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryTealLight : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppTheme.primaryTeal : AppTheme.borderLight,
            width: isSelected ? 2.0 : 1.2,
          ),
          boxShadow: isSelected ? AppTheme.cardShadow : [],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryTeal : circleColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.primaryTealDark : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryTeal
                          : const Color(0xFFE1E8EE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isSelected ? 'Selected Role' : badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : const Color(0xFF3D6B8C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _specialtyController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Widget _buildWelcomePortalScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Column(
        children: [
          // Top Curved Teal Gradient Hero Header
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 52, 24, 58),
                decoration: const BoxDecoration(
                  gradient: AppTheme.tealHeaderGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.elliptical(260, 48),
                    bottomRight: Radius.elliptical(260, 48),
                  ),
                ),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.topRight,
                      child: ThemeModeToggleButton(iconColor: Colors.white),
                    ),
                    Container(
                      width: 88,
                      height: 88,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: const PawHeartbeatMotif(size: 64, animate: true),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PurrSync',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Boutique Feline Health & Vet Clinic Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppTheme.borderLight, width: 1.2),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.borderLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Welcome to PurrSync!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select your account portal to get started:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildPortalOptionCard(
                      isSelected: _selectedRole == UserRole.owner,
                      title: 'Pet Owner Portal',
                      description:
                          'Track multi-cat vaccinations, weight trends, QR health cards & book visits.',
                      badgeText: 'Cat Parent Portal',
                      icon: Icons.pets,
                      circleColor: AppTheme.primaryTeal,
                      onTap: () {
                        _selectPortalRole(UserRole.owner);
                        setState(() => _showPortalWelcome = false);
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildPortalOptionCard(
                      isSelected: _selectedRole.isProvider,
                      title: 'Vet / Clinic Provider',
                      description:
                          'Manage clinic hours, service catalog, appointments & community notices.',
                      badgeText: 'Healthcare Portal',
                      icon: Icons.add,
                      circleColor: const Color(0xFF3D6B8C),
                      onTap: () {
                        _selectPortalRole(UserRole.vet);
                        setState(() => _showPortalWelcome = false);
                      },
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      onPressed: () {
                        FirebaseService.selectedPortalRole = _selectedRole;
                        setState(() => _showPortalWelcome = false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Continue to PurrSync  ->',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showPortalWelcome) {
      return _buildWelcomePortalScreen();
    }
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _errorMessage = null;
                          _showPortalWelcome = true;
                        }),
                        icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                        label: const Text(
                          'Change Portal',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ThemeModeToggleButton(iconColor: AppTheme.textPrimaryColor(context)),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedRole.isProvider
                                  ? const Color(0xFFE3EDF5)
                                  : AppTheme.primaryTealLight,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedRole.isProvider
                                    ? const Color(0xFF3D6B8C)
                                    : AppTheme.primaryTeal,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedRole.isProvider ? Icons.local_hospital : Icons.pets,
                                  size: 14,
                                  color: _selectedRole.isProvider
                                      ? const Color(0xFF3D6B8C)
                                      : AppTheme.primaryTealDark,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedRole.isProvider
                                      ? 'Vet / Clinic Portal'
                                      : 'Pet Owner Portal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedRole.isProvider
                                        ? const Color(0xFF3D6B8C)
                                        : AppTheme.primaryTealDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  FadeInSlide(
                    direction: AxisDirection.down,
                    duration: const Duration(milliseconds: 600),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryTealLight,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.15)),
                            ),
                            child: Icon(
                              _selectedRole.isProvider ? Icons.medical_services_outlined : Icons.pets,
                              size: 36,
                              color: AppTheme.primaryTeal,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'PurrSync',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.6,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedRole.isProvider
                              ? 'Veterinary & Clinic Provider Portal'
                              : 'Pet Owner & Cat Parent Portal',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Account Mode Toggle Bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_isLogin) {
                                setState(() {
                                  _isLogin = true;
                                  _errorMessage = null;
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isLogin ? AppTheme.surface : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: _isLogin ? AppTheme.cardShadow : [],
                              ),
                              child: Text(
                                'Sign In',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _isLogin ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_isLogin) {
                                setState(() {
                                  _isLogin = false;
                                  _errorMessage = null;
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isLogin ? AppTheme.surface : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: !_isLogin ? AppTheme.cardShadow : [],
                              ),
                              child: Text(
                                'Create Account',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: !_isLogin ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Registration fields locked to chosen portal context
                  if (!_isLogin) ...[
                    // Full Name / Business Name
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: _selectedRole.isProvider
                            ? 'Clinic / Veterinarian Name *'
                            : 'Full Name *',
                        prefixIcon: Icon(
                          _selectedRole.isProvider ? Icons.local_hospital_outlined : Icons.person,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                      validator: (v) => _validateRequired(
                        v,
                        _selectedRole.isProvider ? 'Clinic or Vet Name' : 'Full Name',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Additional fields for Vet and Clinic
                    if (_selectedRole == UserRole.vet || _selectedRole == UserRole.clinic) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone *',
                                prefixIcon: Icon(Icons.phone, color: AppTheme.primaryTeal),
                              ),
                              validator: (v) => _validateRequired(v, 'Phone number'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _cityController,
                              decoration: const InputDecoration(
                                labelText: 'City *',
                                prefixIcon: Icon(Icons.location_city, color: AppTheme.primaryTeal),
                              ),
                              validator: (v) => _validateRequired(v, 'City'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Address *',
                          prefixIcon: Icon(Icons.home, color: AppTheme.primaryTeal),
                        ),
                        validator: (v) => _validateRequired(v, 'Address'),
                      ),
                      const SizedBox(height: 14),

                      // Clock dial operating hours selector
                      OperatingHoursSelector(
                        openTime: _openTime,
                        closeTime: _closeTime,
                        openDays: _openDays,
                        onOpenTimeChanged: (val) => setState(() => _openTime = val),
                        onCloseTimeChanged: (val) => setState(() => _closeTime = val),
                        onOpenDaysChanged: (val) => setState(() => _openDays = val),
                      ),
                      const SizedBox(height: 14),

                      if (_selectedRole.isProvider) ...[
                        TextFormField(
                          controller: _specialtyController,
                          decoration: const InputDecoration(
                            labelText: 'Specialty (optional, e.g. Feline Surgeon)',
                            prefixIcon: Icon(Icons.star_border, color: AppTheme.primaryTeal),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Visit Types Handled *',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _availableVisitTypes.map((type) {
                            final isSelected = _selectedVisitTypes.contains(type);
                            return FilterChip(
                              label: Text(
                                type,
                                style: TextStyle(
                                  color: isSelected ? AppTheme.primaryTealDark : AppTheme.textSecondary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppTheme.primaryTealLight,
                              checkmarkColor: AppTheme.primaryTeal,
                              backgroundColor: AppTheme.surfaceMuted,
                              side: BorderSide(
                                color: isSelected ? AppTheme.primaryTeal : AppTheme.borderLight,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedVisitTypes.add(type);
                                  } else {
                                    _selectedVisitTypes.remove(type);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ],

                      TextFormField(
                        controller: _bioController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'About / Bio (optional)',
                          prefixIcon: Icon(Icons.info_outline, color: AppTheme.primaryTeal),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],

                  // Common Email & Password
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address *',
                      prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryTeal),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password *',
                      prefixIcon: Icon(Icons.lock_outline, color: AppTheme.primaryTeal),
                    ),
                    validator: _validatePassword,
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        border: Border.all(color: const Color(0xFFEF9A9A)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Color(0xFFC62828), fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          if (_errorMessage!.startsWith('Access Denied:')) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _selectPortalRole(
                                  _selectedRole.isProvider ? UserRole.owner : UserRole.vet,
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppTheme.primaryTealDark,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                icon: const Icon(Icons.swap_horiz, size: 16),
                                label: Text(
                                  _selectedRole.isProvider
                                      ? 'Switch to Pet Owner Portal'
                                      : 'Switch to Vet / Clinic Portal',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _isLoading
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _isLogin
                                  ? (_selectedRole.isProvider
                                      ? 'Sign In to Vet / Clinic Portal'
                                      : 'Sign In to Pet Owner Portal')
                                  : 'Register as ${_selectedRole.displayName}',
                              key: ValueKey('${_isLogin}_${_selectedRole.name}'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.borderLight, thickness: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or continue with',
                          style: TextStyle(fontSize: 12, color: AppTheme.textTertiary, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(child: Divider(color: AppTheme.borderLight, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      backgroundColor: AppTheme.surface,
                      foregroundColor: AppTheme.textPrimary,
                    ),
                    icon: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                      ),
                    ),
                    label: const Text(
                      'Sign in with Google',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
