import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../models/farmer_profile.dart';
import '../../../../models/profile.dart';
import '../farmer_profile_service.dart';

class FarmerProfileEditScreen extends ConsumerStatefulWidget {
  final FarmerProfile profile;

  const FarmerProfileEditScreen({super.key, required this.profile});

  @override
  ConsumerState<FarmerProfileEditScreen> createState() =>
      _FarmerProfileEditScreenState();
}

class _FarmerProfileEditScreenState
    extends ConsumerState<FarmerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();

  final _locationService = LocationService();
  final _avatarService = AvatarService();
  final _imagePicker = ImagePicker();
  final _farmerService = FarmerProfileService();

  String _preferredLanguage = 'en';

  late Future<List<Crop>> _cropsFuture;
  late Set<String> _selectedCropIds;

  Uint8List? _avatarBytes;
  String? _avatarFileName;
  String? _existingAvatarUrl;

  GeoPoint? _locationPoint;
  String? _locationText;

  bool _isFetchingLocation = false;
  String? _locationError;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _selectedCropIds = widget.profile.crops.map((c) => c.id).toSet();
    _cropsFuture = _farmerService.fetchAllCrops();

    _loadGenericProfile();
  }

  Future<void> _loadGenericProfile() async {
    try {
      final authService = ref.read(authServiceProvider);
      final profile = await authService.fetchOwnProfile();

      if (!mounted || profile == null) return;

      _firstNameController.text = profile.firstName;
      _lastNameController.text = profile.lastName;
      _phoneController.text = profile.phone ?? '';

      _addressLine1Controller.text = profile.address.line1 ?? '';
      _addressLine2Controller.text = profile.address.line2 ?? '';
      _cityController.text = profile.address.city ?? '';
      _postalCodeController.text = profile.address.postalCode ?? '';

      _preferredLanguage = profile.preferredLanguage;

      _existingAvatarUrl = profile.avatarUrl;
      _locationPoint = profile.locationPoint;
      _locationText = profile.locationText;

      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();

    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();

    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();

    setState(() {
      _avatarBytes = bytes;
      _avatarFileName = picked.name;
    });
  }

  void _showAvatarSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text('take_photo'.tr()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('choose_from_gallery'.tr()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _locationError = null;
    });

    try {
      final result = await _locationService.fetchCurrentLocation();

      setState(() {
        _locationPoint = result.point;
        _locationText = result.displayText;
      });
    } on LocationException catch (e) {
      setState(() {
        _locationError = e.code.tr();
      });
    } catch (_) {
      setState(() {
        _locationError = 'error_location_unknown'.tr();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCropIds.isEmpty) {
      setState(() => _errorMessage = 'error_select_at_least_one_crop'.tr());
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final userId = authService.currentUser!.id;

      String? avatarPath = _existingAvatarUrl;

      if (_avatarBytes != null) {
        avatarPath = await _avatarService.upload(
          userId: userId,
          bytes: _avatarBytes!,
          fileName: _avatarFileName ?? 'avatar.jpg',
        );
      }

      final genericProfile = Profile(
        id: userId,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        address: Address(
          line1: _addressLine1Controller.text.trim().isEmpty
              ? null
              : _addressLine1Controller.text.trim(),
          line2: _addressLine2Controller.text.trim().isEmpty
              ? null
              : _addressLine2Controller.text.trim(),
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          postalCode: _postalCodeController.text.trim().isEmpty
              ? null
              : _postalCodeController.text.trim(),
        ),
        avatarUrl: avatarPath,
        preferredLanguage: _preferredLanguage,
        activeRole: null,
        locationText: _locationText,
        locationPoint: _locationPoint,
      );

      await authService.updateOwnProfile(genericProfile);

      await _farmerService.updateCrops(userId, _selectedCropIds.toList());

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildCropSection(
    BuildContext context, {
    required String titleKey,
    required List<Crop> crops,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleKey.tr(), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: crops
              .map(
                (crop) => FilterChip(
                  label: Text(crop.name),
                  selected: _selectedCropIds.contains(crop.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedCropIds.add(crop.id);
                    } else {
                      _selectedCropIds.remove(crop.id);
                    }
                  }),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('edit_profile'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // -------------------------------------------------------
                    // Avatar
                    // -------------------------------------------------------

                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundImage: _avatarBytes != null
                                ? MemoryImage(_avatarBytes!)
                                : null,
                            child: _avatarBytes == null
                                ? const Icon(Icons.person, size: 48)
                                : null,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: Theme.of(context).colorScheme.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _showAvatarSourceSheet,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // -------------------------------------------------------
                    // Generic profile
                    // -------------------------------------------------------
                    AppTextField(
                      label: 'first_name'.tr(),
                      controller: _firstNameController,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'error_required'.tr();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    AppTextField(
                      label: 'last_name'.tr(),
                      controller: _lastNameController,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'error_required'.tr();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    AppTextField(
                      label: 'phone'.tr(),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),

                    const SizedBox(height: 24),

                    // -------------------------------------------------------
                    // Address
                    // -------------------------------------------------------
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'address'.tr(),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),

                    const SizedBox(height: 8),

                    AppTextField(
                      label: 'address_line1'.tr(),
                      controller: _addressLine1Controller,
                    ),

                    const SizedBox(height: 16),

                    AppTextField(
                      label: 'address_line2'.tr(),
                      controller: _addressLine2Controller,
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'city'.tr(),
                            controller: _cityController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'postal_code'.tr(),
                            controller: _postalCodeController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // -------------------------------------------------------
                    // Location
                    // -------------------------------------------------------
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'location'.tr(),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),

                    const SizedBox(height: 8),

                    OutlinedButton.icon(
                      onPressed: _isFetchingLocation
                          ? null
                          : _useCurrentLocation,
                      icon: _isFetchingLocation
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        _isFetchingLocation
                            ? 'fetching_location'.tr()
                            : 'use_current_location'.tr(),
                      ),
                    ),

                    if (_locationText != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.place, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_locationText!)),
                        ],
                      ),
                    ],

                    if (_locationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _locationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // -------------------------------------------------------
                    // Language
                    // -------------------------------------------------------
                    Text(
                      'language'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),

                    const SizedBox(height: 8),

                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'en', label: Text('EN')),
                        ButtonSegment(value: 'si', label: Text('SI')),
                        ButtonSegment(value: 'ta', label: Text('TA')),
                      ],
                      selected: {_preferredLanguage},
                      onSelectionChanged: (s) {
                        setState(() {
                          _preferredLanguage = s.first;
                        });
                      },
                    ),

                    const SizedBox(height: 24),

                    // -------------------------------------------------------
                    // Farmer profile — crops grown
                    // -------------------------------------------------------
                    Text(
                      'crops_grown'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),

                    const SizedBox(height: 8),

                    FutureBuilder<List<Crop>>(
                      future: _cropsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return Text(snapshot.error.toString());
                        }

                        final crops = snapshot.data ?? [];
                        final vegetables = crops
                            .where((c) => c.category == 'vegetable')
                            .toList();
                        final fruits = crops
                            .where((c) => c.category == 'fruit')
                            .toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCropSection(
                              context,
                              titleKey: 'crop_category_vegetable',
                              crops: vegetables,
                            ),
                            const SizedBox(height: 16),
                            _buildCropSection(
                              context,
                              titleKey: 'crop_category_fruit',
                              crops: fruits,
                            ),
                          ],
                        );
                      },
                    ),

                    // -------------------------------------------------------
                    // Error
                    // -------------------------------------------------------
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // -------------------------------------------------------
                    // Save
                    // -------------------------------------------------------
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('save'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
