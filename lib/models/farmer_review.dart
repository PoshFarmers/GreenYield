/// Mirrors one row of `farmer_review` — a buyer's optional rating/comment
/// for a farmer, tied to one delivered order. Writes go through the
/// `submit_farmer_review` RPC (see `FarmerReviewService`), never a direct
/// insert/update, so this model is read-only from the client.
class FarmerReview {
  final String id;
  final String orderId;
  final String buyerProfileId;
  final String farmerProfileId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FarmerReview({
    required this.id,
    required this.orderId,
    required this.buyerProfileId,
    required this.farmerProfileId,
    required this.rating,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FarmerReview.fromMap(Map<String, dynamic> map) {
    return FarmerReview(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      buyerProfileId: map['buyer_profile_id'] as String,
      farmerProfileId: map['farmer_profile_id'] as String,
      rating: (map['rating'] as num?)?.toInt() ?? 0,
      comment: map['comment'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Mirrors the `avg_rating`/`review_count` columns denormalized onto
/// `farmer_profile` — trigger-maintained from `farmer_review`, see
/// `supabase/migrations/20260916120000_farmer_review.sql`.
class FarmerRatingSummary {
  final double avgRating;
  final int reviewCount;

  const FarmerRatingSummary({
    required this.avgRating,
    required this.reviewCount,
  });

  factory FarmerRatingSummary.fromMap(Map<String, dynamic> map) {
    return FarmerRatingSummary(
      avgRating: (map['avg_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
    );
  }
}
