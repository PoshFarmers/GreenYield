/// Mirrors the `pricing_rule` table — the flat-rate delivery pricing
/// formula: fee = base_fee + distance_km * per_km_rate, clamped to
/// [min_fee, max_fee]. Synced read-only via the `pricing_rules`
/// PowerSync stream; clients never write to this table.
class PricingRule {
  final String id;
  final String name;
  final double baseFee;
  final double perKmRate;
  final double? minFee;
  final double? maxFee;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final bool isActive;

  const PricingRule({
    required this.id,
    required this.name,
    required this.baseFee,
    required this.perKmRate,
    this.minFee,
    this.maxFee,
    required this.effectiveFrom,
    this.effectiveTo,
    required this.isActive,
  });

  factory PricingRule.fromMap(Map<String, dynamic> map) {
    return PricingRule(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      baseFee: (map['base_fee'] as num?)?.toDouble() ?? 0,
      perKmRate: (map['per_km_rate'] as num?)?.toDouble() ?? 0,
      minFee: (map['min_fee'] as num?)?.toDouble(),
      maxFee: (map['max_fee'] as num?)?.toDouble(),
      effectiveFrom:
          DateTime.tryParse(map['effective_from'] as String? ?? '') ??
          DateTime.now(),
      effectiveTo: map['effective_to'] == null
          ? null
          : DateTime.tryParse(map['effective_to'] as String),
      isActive: ((map['is_active'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
