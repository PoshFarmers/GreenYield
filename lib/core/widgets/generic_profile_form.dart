import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../location/location_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/avatar_image.dart';
import '../../models/profile.dart';

/// Holds all state for the "generic profile" portion of a profile
/// edit screen (name, phone, address, avatar, location, language) —
/// shared across buyer/driver/farmer edit screens rather than
/// duplicated in each. A ChangeNotifier so [GenericProfileFormSection]
/// can rebuild on avatar pick / location fetch without the parent
/// screen needing to know about those internals.
class GenericProfileFormController extends ChangeNotifier {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressLine1Controller = TextEditingController();
  final addressLine2Controller = TextEditingController();
  final cityController = TextEditingController();
  final postalCodeController = TextEditingController();

  final _locationService = LocationService();
  final _imagePicker = ImagePicker();

  String preferredLanguage = 'en';
  Uint8List? avatarBytes;
  String? avatarFileName;
  String? existingAvatarUrl;
  GeoPoint? locationPoint;
  String? locationText;
  bool isFetchingLocation = false;
  String? locationError;

  /// Populates every field from an existing [Profile] — call once,
  /// typically after an async fetch in the parent screen's initState.
  void loadFrom(Profile profile) {
    firstNameController.text = profile.firstName;
    lastNameController.text = profile.lastName;
    phoneController.text = profile.phone ?? '';
    addressLine1Controller.text = profile.address.line1 ?? '';
    addressLine2Controller.text = profile.address.line2 ?? '';
    cityController.text = profile.address.city ?? '';
    postalCodeController.text = profile.address.postalCode ?? '';
    preferredLanguage = profile.preferredLanguage;
    existingAvatarUrl = profile.avatarUrl;
    locationPoint = profile.locationPoint;
    locationText = profile.locationText;
    notifyListeners();
  }

  void setPreferredLanguage(String lang) {
    preferredLanguage = lang;
    notifyListeners();
  }

  Future<void> pickAvatar(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    avatarBytes = await picked.readAsBytes();
    avatarFileName = picked.name;
    notifyListeners();
  }

  Future<void> useCurrentLocation() async {
    isFetchingLocation = true;
    locationError = null;
    notifyListeners();

    try {
      final result = await _locationService.fetchCurrentLocation();
      locationPoint = result.point;
      locationText = result.displayText;
    } on LocationException catch (e) {
      locationError = e.code.tr();
    } catch (_) {
      locationError = 'error_location_unknown'.tr();
    } finally {
      isFetchingLocation = false;
      notifyListeners();
    }
  }

  /// Builds a [Profile] from current field values. Callers that upload
  /// a new avatar should set [existingAvatarUrl] to the new path
  /// *before* calling this, since it's used as-is for avatarUrl.
  Profile buildProfile(String userId) {
    return Profile(
      id: userId,
      firstName: firstNameController.text.trim(),
      lastName: lastNameController.text.trim(),
      phone: phoneController.text.trim().isEmpty
          ? null
          : phoneController.text.trim(),
      address: Address(
        line1: addressLine1Controller.text.trim().isEmpty
            ? null
            : addressLine1Controller.text.trim(),
        line2: addressLine2Controller.text.trim().isEmpty
            ? null
            : addressLine2Controller.text.trim(),
        city: cityController.text.trim().isEmpty
            ? null
            : cityController.text.trim(),
        postalCode: postalCodeController.text.trim().isEmpty
            ? null
            : postalCodeController.text.trim(),
      ),
      avatarUrl: existingAvatarUrl,
      preferredLanguage: preferredLanguage,
      activeRole: null,
      locationText: locationText,
      locationPoint: locationPoint,
    );
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    phoneController.dispose();
    addressLine1Controller.dispose();
    addressLine2Controller.dispose();
    cityController.dispose();
    postalCodeController.dispose();
    super.dispose();
  }
}

/// Renders the avatar picker, name/phone/address/location/language
/// fields for [controller]. Place inside a `Form` — validators for
/// first/last name are wired in here.
class GenericProfileFormSection extends StatelessWidget {
  final GenericProfileFormController controller;

  const GenericProfileFormSection({super.key, required this.controller});

  void _showAvatarSourceSheet(BuildContext context) {
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
                controller.pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('choose_from_gallery'.tr()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.pickAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  controller.avatarBytes != null
                      ? CircleAvatar(
                          radius: 48,
                          backgroundImage: MemoryImage(controller.avatarBytes!),
                        )
                      : AvatarImage(
                          path: controller.existingAvatarUrl,
                          radius: 48,
                        ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _showAvatarSourceSheet(context),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.edit,
                            size: 18,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            AppTextField(
              label: 'first_name'.tr(),
              controller: controller.firstNameController,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'error_required'.tr()
                  : null,
            ),

            const SizedBox(height: 16),

            AppTextField(
              label: 'last_name'.tr(),
              controller: controller.lastNameController,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'error_required'.tr()
                  : null,
            ),

            const SizedBox(height: 16),

            AppTextField(
              label: 'phone'.tr(),
              controller: controller.phoneController,
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 24),

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
              controller: controller.addressLine1Controller,
            ),

            const SizedBox(height: 16),

            AppTextField(
              label: 'address_line2'.tr(),
              controller: controller.addressLine2Controller,
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'city'.tr(),
                    controller: controller.cityController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'postal_code'.tr(),
                    controller: controller.postalCodeController,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'location'.tr(),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: controller.isFetchingLocation
                  ? null
                  : controller.useCurrentLocation,
              icon: controller.isFetchingLocation
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(
                controller.isFetchingLocation
                    ? 'fetching_location'.tr()
                    : 'use_current_location'.tr(),
              ),
            ),

            if (controller.locationText != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.place, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(controller.locationText!)),
                ],
              ),
            ],

            if (controller.locationError != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.locationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 24),

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
              selected: {controller.preferredLanguage},
              onSelectionChanged: (s) =>
                  controller.setPreferredLanguage(s.first),
            ),
          ],
        );
      },
    );
  }
}
