import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_text_field.dart';
import '../card_input_utils.dart';
import '../models/linked_card.dart';
import '../payment_gateway.dart';
import '../payment_providers.dart';

/// Opens the add-card sheet. Returns the created card, or null if dismissed.
///
/// [showSaveOption] adds a "Save this card for later" switch; when it is off
/// the card is a one-off (used for "add new card" at checkout).
Future<LinkedCard?> showAddCardSheet(
  BuildContext context, {
  bool showSaveOption = false,
}) {
  return showModalBottomSheet<LinkedCard>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddCardSheet(showSaveOption: showSaveOption),
  );
}

class AddCardSheet extends ConsumerStatefulWidget {
  final bool showSaveOption;

  const AddCardSheet({super.key, this.showSaveOption = false});

  @override
  ConsumerState<AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends ConsumerState<AddCardSheet> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
  final _holder = TextEditingController();
  final _nickname = TextEditingController();

  bool _makeDefault = false;
  bool _save = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    _cvc.dispose();
    _holder.dispose();
    _nickname.dispose();
    super.dispose();
  }

  void _fillTestCard(TestCard card) {
    final brand = detectBrand(card.number);
    final year = (DateTime.now().year + 3) % 100;
    setState(() {
      _number.text = formatCardNumber(card.number, brand);
      _expiry.text = '12/${year.toString().padLeft(2, '0')}';
      _cvc.text = '123';
      if (_holder.text.trim().isEmpty) _holder.text = 'Test User';
      _error = null;
    });
  }

  String? _validateNumber(String? value) {
    final digits = digitsOnly(value ?? '');
    final brand = detectBrand(digits);
    final validLength = brand == CardBrand.amex
        ? digits.length == 15
        : digits.length >= 13 && digits.length <= 19;
    if (!validLength || !luhnValid(digits)) {
      return 'payments_error_invalid_card_number'.tr();
    }
    return null;
  }

  String? _validateExpiry(String? value) {
    final expiry = parseExpiry(value ?? '');
    if (expiry == null || expiry.year > DateTime.now().year + 20) {
      return 'payments_error_invalid_expiry'.tr();
    }
    if (isCardExpired(expiry.month, expiry.year)) {
      return 'payments_error_card_expired'.tr();
    }
    return null;
  }

  String? _validateCvc(String? value) {
    if (!RegExp(r'^\d{3,4}$').hasMatch(value ?? '')) {
      return 'payments_error_invalid_cvc'.tr();
    }
    return null;
  }

  String? _validateHolder(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 2 || length > 80) {
      return 'payments_error_invalid_holder_name'.tr();
    }
    return null;
  }

  String? _validateNickname(String? value) {
    if ((value ?? '').trim().length > 40) {
      return 'payments_error_invalid_nickname'.tr();
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final expiry = parseExpiry(_expiry.text)!;
    final nickname = _nickname.text.trim();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final card = await ref
          .read(linkedCardServiceProvider)
          .add(
            NewCardInput(
              number: digitsOnly(_number.text),
              expMonth: expiry.month,
              expYear: expiry.year,
              cvc: _cvc.text,
              holderName: _holder.text.trim(),
              nickname: nickname.isEmpty ? null : nickname,
              makeDefault: _save && _makeDefault,
              save: _save,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(card);
    } on PaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('payments_add_card'.tr(), style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              _TestModeBanner(onPick: _fillTestCard),
              const SizedBox(height: 16),
              AppTextField(
                label: 'payments_card_number'.tr(),
                controller: _number,
                keyboardType: TextInputType.number,
                hintText: '1234 5678 9012 3456',
                inputFormatters: [CardNumberFormatter()],
                validator: _validateNumber,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'payments_expiry'.tr(),
                      controller: _expiry,
                      keyboardType: TextInputType.number,
                      hintText: 'payments_expiry_hint'.tr(),
                      inputFormatters: [ExpiryDateFormatter()],
                      validator: _validateExpiry,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      label: 'payments_cvc'.tr(),
                      controller: _cvc,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: _validateCvc,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'payments_holder_name'.tr(),
                controller: _holder,
                keyboardType: TextInputType.name,
                validator: _validateHolder,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'payments_nickname'.tr(),
                controller: _nickname,
                hintText: 'payments_nickname_hint'.tr(),
                validator: _validateNickname,
              ),
              if (widget.showSaveOption)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('payments_save_card'.tr()),
                  value: _save,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _save = value),
                ),
              if (_save)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('payments_make_default'.tr()),
                  value: _makeDefault,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _makeDefault = value),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('payments_add_card_action'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsible "test mode" panel listing the mock-gateway test cards. Tapping
/// one fills the form. TEST MODE ONLY: remove when swapping to a real gateway.
class _TestModeBanner extends StatelessWidget {
  final ValueChanged<TestCard> onPick;

  const _TestModeBanner({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            Icons.science_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          title: Text(
            'payments_test_mode_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          subtitle: Text(
            'payments_test_mode_body'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          children: [
            for (final card in kTestCards)
              ListTile(
                dense: true,
                title: Text(
                  formatCardNumber(card.number, detectBrand(card.number)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                subtitle: Text(
                  card.labelKey.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                onTap: () => onPick(card),
              ),
          ],
        ),
      ),
    );
  }
}
