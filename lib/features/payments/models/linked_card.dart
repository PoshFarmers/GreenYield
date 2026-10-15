enum CardBrand {
  visa('Visa'),
  mastercard('Mastercard'),
  amex('American Express'),
  discover('Discover'),
  other('Card');

  final String label;

  const CardBrand(this.label);

  static CardBrand fromDb(String? value) => CardBrand.values.firstWhere(
    (brand) => brand.name == value,
    orElse: () => CardBrand.other,
  );
}

/// A card is valid through the last day of its expiry month. Mirrors the
/// server-side `mockgw_card_expired` check.
bool isCardExpired(int month, int year, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final firstDayAfterExpiry = DateTime(year, month + 1, 1);
  return !firstDayAfterExpiry.isAfter(today);
}

/// A saved card as returned by `list_linked_cards` / `add_linked_card`.
/// Never contains the PAN, CVC or gateway token.
class LinkedCard {
  final String id;
  final CardBrand brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final String holderName;
  final String? nickname;
  final bool isDefault;
  final bool isExpired;
  final DateTime? createdAt;

  const LinkedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.holderName,
    this.nickname,
    required this.isDefault,
    required this.isExpired,
    this.createdAt,
  });

  String get title => (nickname != null && nickname!.isNotEmpty)
      ? nickname!
      : '${brand.label} •••• $last4';

  String get maskedNumber => '•••• $last4';

  String get expiryLabel =>
      '${expMonth.toString().padLeft(2, '0')}/'
      '${(expYear % 100).toString().padLeft(2, '0')}';

  factory LinkedCard.fromMap(Map<String, dynamic> map) {
    final expMonth = (map['exp_month'] as num).toInt();
    final expYear = (map['exp_year'] as num).toInt();
    final createdAt = map['created_at'] as String?;
    return LinkedCard(
      id: map['id'] as String,
      brand: CardBrand.fromDb(map['brand'] as String?),
      last4: map['last4'] as String,
      expMonth: expMonth,
      expYear: expYear,
      holderName: (map['holder_name'] as String?) ?? '',
      nickname: map['nickname'] as String?,
      isDefault: (map['is_default'] as bool?) ?? false,
      isExpired:
          (map['is_expired'] as bool?) ?? isCardExpired(expMonth, expYear),
      createdAt: createdAt == null ? null : DateTime.tryParse(createdAt),
    );
  }
}
