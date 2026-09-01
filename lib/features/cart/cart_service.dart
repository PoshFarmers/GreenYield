import 'package:uuid/uuid.dart';

import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/cart_item.dart';

/// Sprint 2 — Task 3.1: Cart Management.
///
/// Entirely local-first, like the rest of the app: every read/write here
/// hits the on-device PowerSync mirror (`cart`, `cart_item`, joined
/// against `produce_listing`/`crop`), never Supabase directly. Writes go
/// through PowerSync's CRUD queue and sync out via `SupabaseConnector`
/// once connectivity returns — the buyer can build/edit a cart entirely
/// offline.
///
/// One cart per buyer (`cart.buyer_profile_id` is `unique`), matching
/// the architecture doc: a single cart can hold items from several
/// farmers at once, split into one order per farmer only at checkout
/// (Task 3.2, not this branch).
class CartService {
  static const _uuid = Uuid();

  const CartService();

  /// Returns this buyer's cart id, creating the row on first use.
  Future<String> ensureCart(String buyerProfileId) async {
    final existing = await db.getOptional(
      'SELECT id FROM cart WHERE buyer_profile_id = ?',
      [buyerProfileId],
    );
    if (existing != null) return existing['id'] as String;

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.execute(
      'INSERT INTO cart (id, buyer_profile_id, created_at, updated_at) '
      'VALUES (?, ?, ?, ?)',
      [id, buyerProfileId, now, now],
    );
    return id;
  }

  /// Every item in [buyerProfileId]'s cart, newest-added first, joined
  /// with the live listing/crop data needed to render it. Reactive —
  /// updates automatically as items are added/changed/removed, or as
  /// the underlying listing's price/stock changes.
  Stream<List<CartLineItem>> watchCartItems(String buyerProfileId) {
    return db
        .watch(
          '''
      SELECT
        ci.id,
        ci.produce_listing_id,
        ci.quantity_kg,
        ci.created_at,
        pl.farmer_profile_id,
        pl.crop_id,
        c.name        AS crop_name,
        c.category    AS crop_category,
        pl.price_per_kg,
        pl.available_quantity_kg,
        pl.status_text,
        pl.image_url
      FROM cart_item ci
      JOIN cart c2 ON c2.id = ci.cart_id
      JOIN produce_listing pl ON pl.id = ci.produce_listing_id
      JOIN crop c ON c.id = pl.crop_id
      WHERE c2.buyer_profile_id = ?
      ORDER BY ci.created_at DESC
      ''',
          parameters: [buyerProfileId],
        )
        .map((rows) => rows.map(CartLineItem.fromMap).toList());
  }

  /// Total item count across the whole cart — for a nav-bar badge.
  Stream<double> watchItemCount(String buyerProfileId) {
    return db
        .watch(
          '''
      SELECT COALESCE(SUM(ci.quantity_kg), 0) AS total
      FROM cart_item ci
      JOIN cart c2 ON c2.id = ci.cart_id
      WHERE c2.buyer_profile_id = ?
      ''',
          parameters: [buyerProfileId],
        )
        .map((rows) {
          final value = rows.first['total'];
          return value is num ? value.toDouble() : 0.0;
        });
  }

  /// Adds [quantityKg] of a listing to the cart, or — if that listing is
  /// already in the cart — increases its existing quantity by
  /// [quantityKg]. Either way the result is clamped to the listing's
  /// current available stock, since it may have moved since the buyer
  /// started browsing.
  Future<void> addToCart({
    required String buyerProfileId,
    required String produceListingId,
    required double quantityKg,
  }) async {
    if (quantityKg <= 0) return;

    final cartId = await ensureCart(buyerProfileId);
    final maxQty = await _availableStock(produceListingId);

    final existing = await db.getOptional(
      'SELECT id, quantity_kg FROM cart_item '
      'WHERE cart_id = ? AND produce_listing_id = ?',
      [cartId, produceListingId],
    );

    final now = DateTime.now().toIso8601String();

    if (existing != null) {
      final currentQty = (existing['quantity_kg'] as num).toDouble();
      final newQty = _clamp(currentQty + quantityKg, maxQty);
      await db.execute(
        'UPDATE cart_item SET quantity_kg = ?, updated_at = ? WHERE id = ?',
        [newQty, now, existing['id']],
      );
      return;
    }

    await db.execute(
      'INSERT INTO cart_item '
      '(id, cart_id, produce_listing_id, quantity_kg, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        cartId,
        produceListingId,
        _clamp(quantityKg, maxQty),
        now,
        now,
      ],
    );
  }

  /// Sets a cart item's quantity outright (used by the stepper on the
  /// cart screen). A quantity of zero or less removes the item.
  Future<void> updateQuantity(String cartItemId, double quantityKg) async {
    if (quantityKg <= 0) {
      await removeItem(cartItemId);
      return;
    }

    final row = await db.getOptional(
      'SELECT produce_listing_id FROM cart_item WHERE id = ?',
      [cartItemId],
    );
    if (row == null) return;

    final maxQty = await _availableStock(row['produce_listing_id'] as String);
    await db.execute(
      'UPDATE cart_item SET quantity_kg = ?, updated_at = ? WHERE id = ?',
      [
        _clamp(quantityKg, maxQty),
        DateTime.now().toIso8601String(),
        cartItemId,
      ],
    );
  }

  Future<void> removeItem(String cartItemId) async {
    await db.execute('DELETE FROM cart_item WHERE id = ?', [cartItemId]);
  }

  /// Removes every item belonging to one farmer from the cart — used by
  /// the "Remove all" action on a farmer group when a listing has gone
  /// stale (sold out / unpublished).
  Future<void> removeFarmerItems(
    String buyerProfileId,
    String farmerProfileId,
  ) async {
    await db.execute(
      '''
      DELETE FROM cart_item
      WHERE cart_id = (SELECT id FROM cart WHERE buyer_profile_id = ?)
        AND produce_listing_id IN (
          SELECT id FROM produce_listing WHERE farmer_profile_id = ?
        )
      ''',
      [buyerProfileId, farmerProfileId],
    );
  }

  Future<double> _availableStock(String produceListingId) async {
    final row = await db.getOptional(
      'SELECT available_quantity_kg FROM produce_listing WHERE id = ?',
      [produceListingId],
    );
    if (row == null) return 0;
    final value = row['available_quantity_kg'];
    return value is num ? value.toDouble() : 0;
  }

  double _clamp(double value, double max) {
    if (max <= 0) return 0;
    return value.clamp(0, max).toDouble();
  }
}
