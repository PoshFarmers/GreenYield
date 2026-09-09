import 'dart:developer' as developer;

import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../core/supabase/client.dart';
import '../../models/farmer_review.dart';

/// Farmer rating & reviews. Reads watch the local PowerSync mirror
/// (read-only). The one write this class exposes, [submitReview], goes
/// through the `submit_farmer_review` RPC rather than writing to
/// `farmer_review` directly — see that migration's doc comment. The RPC
/// both creates a first-time review and edits an existing one (upsert on
/// `order_id`), so there's no separate update method.
class FarmerReviewService {
  const FarmerReviewService();

  /// All reviews for a farmer, newest first — for the farmer's public
  /// profile page.
  Stream<List<FarmerReview>> watchReviewsForFarmer(String farmerProfileId) {
    return db
        .watch(
          'SELECT * FROM farmer_review WHERE farmer_profile_id = ? ORDER BY created_at DESC',
          parameters: [farmerProfileId],
        )
        .map((rows) => rows.map(FarmerReview.fromMap).toList());
  }

  /// The signed-in buyer's own review of [orderId], if any — null means
  /// the order hasn't been reviewed yet. Use this to decide between
  /// showing "Add a review" or "Edit your review" (an order being
  /// `delivered`, see `OrderStatus.isReviewable`, only means reviewing
  /// is *allowed*, not that it hasn't happened yet).
  Stream<FarmerReview?> watchReviewForOrder(String orderId) {
    return db
        .watch(
          'SELECT * FROM farmer_review WHERE order_id = ?',
          parameters: [orderId],
        )
        .map((rows) => rows.isEmpty ? null : FarmerReview.fromMap(rows.first));
  }

  /// One-shot version of [watchReviewForOrder] — used where a stream
  /// would be overkill (e.g. deciding once whether to pop up the
  /// post-delivery review prompt).
  Future<FarmerReview?> getReviewForOrder(String orderId) async {
    final rows = await db.getAll(
      'SELECT * FROM farmer_review WHERE order_id = ?',
      [orderId],
    );
    return rows.isEmpty ? null : FarmerReview.fromMap(rows.first);
  }

  /// The most recent delivered order the signed-in buyer has with this
  /// farmer, if any — used to decide whether "Rate & review" should
  /// appear on the farmer's public profile page at all (only buyers who
  /// have actually completed an order with this farmer may review).
  /// Doesn't account for that order already being reviewed — combine
  /// with [watchReviewForOrder] for that.
  Stream<String?> watchLatestDeliveredOrderId({
    required String buyerProfileId,
    required String farmerProfileId,
  }) {
    return db
        .watch(
          '''
          SELECT id FROM orders
          WHERE buyer_profile_id = ? AND farmer_profile_id = ? AND status = 'delivered'
          ORDER BY placed_at DESC
          LIMIT 1
          ''',
          parameters: [buyerProfileId, farmerProfileId],
        )
        .map((rows) => rows.isEmpty ? null : rows.first['id'] as String);
  }

  /// The farmer's denormalized rating aggregate. Null if the
  /// `farmer_profile` row itself hasn't synced locally yet.
  Stream<FarmerRatingSummary?> watchRatingSummary(String farmerProfileId) {
    return db
        .watch(
          'SELECT avg_rating, review_count FROM farmer_profile WHERE profile_id = ?',
          parameters: [farmerProfileId],
        )
        .map(
          (rows) =>
              rows.isEmpty ? null : FarmerRatingSummary.fromMap(rows.first),
        );
  }

  /// Rates (1-5) and optionally reviews the farmer behind [orderId].
  /// Only valid once that order is delivered — enforced server-side by
  /// `submit_farmer_review`, which also derives the buyer/farmer ids
  /// from the order rather than trusting the client. Calling this again
  /// for the same order edits the existing review in place. Throws on
  /// failure (e.g. order not delivered, or not the caller's order) —
  /// callers should catch and surface the error.
  Future<void> submitReview({
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    developer.log(
      'Calling submit_farmer_review RPC — order: $orderId, rating: $rating',
      name: 'GreenYield.FarmerReviewService',
    );
    await supabase.rpc(
      'submit_farmer_review',
      params: {'p_order_id': orderId, 'p_rating': rating, 'p_comment': comment},
    );
  }
}
