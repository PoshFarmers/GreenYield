class BuyerProfile {
  final String profileId;
  final String buyerType; // 'individual' | 'organization'
  final String? buyerLabel;

  const BuyerProfile({
    required this.profileId,
    required this.buyerType,
    this.buyerLabel,
  });

  factory BuyerProfile.fromMap(Map<String, dynamic> map) {
    return BuyerProfile(
      profileId: map['profile_id'] as String,
      buyerType: map['buyer_type'] as String,
      buyerLabel: map['buyer_label'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'profile_id': profileId,
    'buyer_type': buyerType,
    if (buyerLabel != null) 'buyer_label': buyerLabel,
  };
}
