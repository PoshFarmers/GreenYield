import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/pricing_rule.dart';

/// delivery-cost "stub". Computes a straight
/// formula (base fee + per-km rate, clamped to [min_fee, max_fee])
/// against the distance already returned by the marketplace search/
/// detail RPCs (`MarketplaceListing.distanceKm`), rather than calling
/// any new server endpoint. Fully client-side and offline-capable.
///
/// replace this with a real route-based distance
/// once Delivery & Logistics has journey/route data to draw on.
class DeliveryFeeService {
  const DeliveryFeeService();

  Future<PricingRule?> getActiveRule() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final row = await db.getOptional(
      '''
      SELECT * FROM pricing_rule
      WHERE is_active = 1
        AND effective_from <= ?
        AND (effective_to IS NULL OR effective_to > ?)
      ORDER BY effective_from DESC
      LIMIT 1
      ''',
      [nowIso, nowIso],
    );
    return row == null ? null : PricingRule.fromMap(row);
  }

  Stream<PricingRule?> watchActiveRule() {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return db
        .watch(
          '''
          SELECT * FROM pricing_rule
          WHERE is_active = 1
            AND effective_from <= ?
            AND (effective_to IS NULL OR effective_to > ?)
          ORDER BY effective_from DESC
          LIMIT 1
          ''',
          parameters: [nowIso, nowIso],
        )
        .map((rows) => rows.isEmpty ? null : PricingRule.fromMap(rows.first));
  }

  double applyRule(PricingRule rule, double distanceKm) {
    var fee = rule.baseFee + (distanceKm * rule.perKmRate);
    if (rule.minFee != null && fee < rule.minFee!) fee = rule.minFee!;
    if (rule.maxFee != null && fee > rule.maxFee!) fee = rule.maxFee!;
    return double.parse(fee.toStringAsFixed(2));
  }

  Future<double?> estimateFee(double? distanceKm) async {
    if (distanceKm == null) return null;
    final rule = await getActiveRule();
    if (rule == null) return null;
    return applyRule(rule, distanceKm);
  }
}
