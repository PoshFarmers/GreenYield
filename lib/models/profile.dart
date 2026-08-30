import 'package:flutter/foundation.dart';

import 'dart:convert';

/// Mirrors the `address_type` composite type in Postgres.
class Address {
  final String? line1;
  final String? line2;
  final String? city;
  final String? postalCode;

  const Address({this.line1, this.line2, this.city, this.postalCode});

  bool get isEmpty =>
      (line1 == null || line1!.isEmpty) &&
      (line2 == null || line2!.isEmpty) &&
      (city == null || city!.isEmpty) &&
      (postalCode == null || postalCode!.isEmpty);

  /// Comma-joined, skipping empty parts — the display format used
  /// across every profile view screen.
  String get formatted => [
    line1,
    line2,
    city,
    postalCode,
  ].where((value) => value != null && value.isNotEmpty).join(', ');

  Address copyWith({
    String? line1,
    String? line2,
    String? city,
    String? postalCode,
  }) => Address(
    line1: line1 ?? this.line1,
    line2: line2 ?? this.line2,
    city: city ?? this.city,
    postalCode: postalCode ?? this.postalCode,
  );

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

/// A single lat/lng pair, used for `profile.location_point`
/// (a PostGIS `geography(Point, 4326)` column).
@immutable
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint({required this.latitude, required this.longitude});

  /// PostgREST returns geography columns as GeoJSON when selected
  /// with the default representation.
  factory GeoPoint.fromGeoJson(Map<String, dynamic> json) {
    final coords = (json['coordinates'] as List).cast<num>();
    return GeoPoint(
      longitude: coords[0].toDouble(),
      latitude: coords[1].toDouble(),
    );
  }

  /// EWKT text — Postgres casts this straight to `geography` on insert,
  /// so it can go directly into a PostgREST insert/upsert payload.
  String toEwkt() => 'SRID=4326;POINT($longitude $latitude)';
}

/// Mirrors the generic `profile` table.
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
  final GeoPoint? locationPoint;

  /// Set by the database default on insert — read-only from the client
  /// (never sent in toInsertMap). Used for "member since" display.
  final DateTime? createdAt;

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
    this.locationPoint,
    this.createdAt,
  });

  /// Only used to build the object handed to `createOwnProfile` on the
  /// first completion screen and for the odd local UI tweak — the
  /// source of truth after that is always the PowerSync-backed row.
  Profile copyWith({
    String? firstName,
    String? lastName,
    Address? address,
    String? phone,
    String? avatarUrl,
    String? preferredLanguage,
    String? activeRole,
    String? locationText,
    GeoPoint? locationPoint,
    DateTime? createdAt,
  }) {
    return Profile(
      id: id,
      createdAt: createdAt ?? this.createdAt,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      activeRole: activeRole ?? this.activeRole,
      locationText: locationText ?? this.locationText,
      locationPoint: locationPoint ?? this.locationPoint,
    );
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      address: Address.fromMap(_decodeJson(map['address'])),
      phone: map['phone'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      preferredLanguage: map['preferred_language'] as String? ?? 'en',
      activeRole: map['active_role'] as String?,
      locationText: map['location_text'] as String?,
      locationPoint: map['location_geojson'] == null
          ? null
          : GeoPoint.fromGeoJson(_decodeJson(map['location_geojson'])!),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
    );
  }

  /// For insert into the `profile` table.
  /// `active_role` is intentionally never sent here — it stays null until
  /// role-specific profile tables exist and a role-selection flow is built.
  Map<String, dynamic> toInsertMap() => {
    'id': id,
    'first_name': firstName,
    'last_name': lastName,
    if (!address.isEmpty) 'address': jsonEncode(address.toMap()),
    if (phone != null && phone!.isNotEmpty) 'phone': phone,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    'preferred_language': preferredLanguage,
    if (locationText != null) 'location_text': locationText,
    if (locationPoint != null) 'location_point': locationPoint!.toEwkt(),
  };

  static Map<String, dynamic>? _decodeJson(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) {
      return v;
    } // e.g. if ever read via raw postgrest
    if (v is String && v.isNotEmpty) {
      return jsonDecode(v) as Map<String, dynamic>;
    }
    return null;
  }
}
