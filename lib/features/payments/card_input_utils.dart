import 'package:flutter/services.dart';

import 'models/linked_card.dart';

String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

bool luhnValid(String number) {
  if (number.isEmpty) return false;
  var sum = 0;
  var alternate = false;
  for (var i = number.length - 1; i >= 0; i--) {
    var digit = int.parse(number[i]);
    if (alternate) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

CardBrand detectBrand(String digits) {
  if (digits.startsWith('4')) return CardBrand.visa;
  if (RegExp(r'^5[1-5]').hasMatch(digits)) return CardBrand.mastercard;
  if (digits.length >= 4) {
    final prefix = int.parse(digits.substring(0, 4));
    if (prefix >= 2221 && prefix <= 2720) return CardBrand.mastercard;
  }
  if (RegExp(r'^3[47]').hasMatch(digits)) return CardBrand.amex;
  if (RegExp(r'^(6011|65)').hasMatch(digits)) return CardBrand.discover;
  return CardBrand.other;
}

int maxCardDigits(CardBrand brand) => brand == CardBrand.amex ? 15 : 19;

String formatCardNumber(String digits, CardBrand brand) {
  final groups = brand == CardBrand.amex
      ? const [4, 6, 5]
      : const [4, 4, 4, 4, 3];
  final buffer = StringBuffer();
  var index = 0;
  for (final size in groups) {
    if (index >= digits.length) break;
    if (index > 0) buffer.write(' ');
    final end = index + size > digits.length ? digits.length : index + size;
    buffer.write(digits.substring(index, end));
    index = end;
  }
  return buffer.toString();
}

/// Groups the number as the user types (4-4-4-4, or 4-6-5 for Amex) and keeps
/// the cursor next to the digit being edited.
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = digitsOnly(newValue.text);
    final brand = detectBrand(digits);
    final max = maxCardDigits(brand);
    if (digits.length > max) digits = digits.substring(0, max);

    final formatted = formatCardNumber(digits, brand);

    final rawCursor = newValue.selection.baseOffset;
    final cursor = rawCursor < 0 || rawCursor > newValue.text.length
        ? newValue.text.length
        : rawCursor;
    var digitsBeforeCursor = digitsOnly(newValue.text.substring(0, cursor))
        .length;
    if (digitsBeforeCursor > digits.length) digitsBeforeCursor = digits.length;

    var position = 0;
    var seen = 0;
    while (position < formatted.length && seen < digitsBeforeCursor) {
      if (formatted[position] != ' ') seen++;
      position++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: position),
    );
  }
}

/// Formats as MM/YY. A first digit of 2-9 can only be a month, so it is
/// padded to 0M.
class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = digitsOnly(newValue.text);
    if (digits.length > 4) digits = digits.substring(0, 4);
    if (digits.length == 1 && int.parse(digits) > 1) digits = '0$digits';

    final deleting = newValue.text.length < oldValue.text.length;
    final String text;
    if (digits.length > 2) {
      text = '${digits.substring(0, 2)}/${digits.substring(2)}';
    } else if (digits.length == 2 && !deleting) {
      text = '$digits/';
    } else {
      text = digits;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Parses "MM/YY". Returns null if malformed or the month is out of range.
({int month, int year})? parseExpiry(String text) {
  final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(text.trim());
  if (match == null) return null;
  final month = int.parse(match.group(1)!);
  final year = 2000 + int.parse(match.group(2)!);
  if (month < 1 || month > 12) return null;
  return (month: month, year: year);
}

/// Mock-gateway test cards (see the migration). TEST MODE ONLY.
class TestCard {
  final String number;
  final String labelKey;

  const TestCard(this.number, this.labelKey);
}

const kTestCards = [
  TestCard('4242424242424242', 'payments_test_visa_ok'),
  TestCard('5555555555554444', 'payments_test_mastercard_ok'),
  TestCard('378282246310005', 'payments_test_amex_ok'),
  TestCard('4000000000000002', 'payments_test_declined'),
  TestCard('4000000000009995', 'payments_test_insufficient'),
  TestCard('4000000000000069', 'payments_test_expired'),
  TestCard('4000000000000127', 'payments_test_cvc'),
  TestCard('4000000000000341', 'payments_test_payout_fails'),
];
