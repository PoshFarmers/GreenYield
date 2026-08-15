/// Mirrors the `address_type` composite type in Postgres.
class Address {
  final String? line1;
  final String? line2;
  final String? city;
  final String? postalCode;

  const Address({this.line1, this.line2, this.city, this.postalCode});

  factory Address.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const Address();
    return Address(
      line1: map['line1'] as String?,
      line2: map['line2'] as String?,
      city: map['city'] as String?,
      postalCode: map['postal_code'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'line1': line1,
        'line2': line2,
        'city': city,
        'postal_code': postalCode,
      };
}

/// Mirrors the generic `profile` table
class Profile {
  final String id;
  final String firstName;
  final String lastName;
  final Address address;
  final String? phone;
  final String? avatarUrl;
  final String preferredLanguage; // 'en' | 'si' | 'ta'
  final String? activeRole; // 'farmer' | 'buyer' | 'driver' | null
  final String? locationText;

  const Profile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.address = const Address(),
    this.phone,
    this.avatarUrl,
    this.preferredLanguage = 'en',
    this.activeRole,
    this.locationText,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      address: Address.fromMap(map['address'] as Map<String, dynamic>?),
      phone: map['phone'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      preferredLanguage: map['preferred_language'] as String? ?? 'en',
      activeRole: map['active_role'] as String?,
      locationText: map['location_text'] as String?,
    );
  }

  /// For insert/upsert into the `profile` table
  Map<String, dynamic> toInsertMap() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        if (phone != null) 'phone': phone,
        'preferred_language': preferredLanguage,
        if (locationText != null) 'location_text': locationText,
      };
}