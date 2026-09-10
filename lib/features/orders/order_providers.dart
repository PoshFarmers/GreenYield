import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_detail_models.dart';
import 'order_service.dart';

// ---------------------------------------------------------------------------
// Service singleton
// ---------------------------------------------------------------------------

final _orderService = const OrderService();

// ---------------------------------------------------------------------------
// Status filter constants — match the Postgres ENUM strings exactly.
// ---------------------------------------------------------------------------

const _buyerActiveStatuses = [
  'placed',
  'confirmed',
  'assigned',
  'packed',
  'picked_up',
  'in_transit',
];

const _buyerHistoryStatuses = ['delivered', 'completed', 'cancelled'];

const _farmerToPackStatuses = ['placed', 'confirmed', 'assigned'];

const _farmerInTransitStatuses = ['packed', 'picked_up', 'in_transit'];

const _farmerHistoryStatuses = ['delivered', 'completed', 'cancelled'];

const _driverPickupStatuses = ['assigned', 'packed'];

const _driverActiveStatuses = ['picked_up', 'in_transit'];

const _driverCompletedStatuses = ['delivered', 'completed', 'cancelled'];

// ---------------------------------------------------------------------------
// Buyer providers
// ---------------------------------------------------------------------------

/// Active orders for a buyer (placed → in_transit).
final buyerActiveOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, String>((ref, buyerProfileId) {
      return _orderService.watchOrdersForBuyer(
        buyerProfileId: buyerProfileId,
        statuses: _buyerActiveStatuses,
      );
    });

/// History orders for a buyer (delivered, completed, cancelled).
final buyerHistoryOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, String>((ref, buyerProfileId) {
      return _orderService.watchOrdersForBuyer(
        buyerProfileId: buyerProfileId,
        statuses: _buyerHistoryStatuses,
      );
    });

// ---------------------------------------------------------------------------
// Farmer providers
// ---------------------------------------------------------------------------

/// Orders the farmer needs to pack (placed, confirmed, assigned).
final farmerToPackOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, String>((ref, farmerProfileId) {
      return _orderService.watchOrdersForFarmer(
        farmerProfileId: farmerProfileId,
        statuses: _farmerToPackStatuses,
      );
    });

/// Orders the farmer has packed or that are in transit.
final farmerInTransitOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, String>((ref, farmerProfileId) {
      return _orderService.watchOrdersForFarmer(
        farmerProfileId: farmerProfileId,
        statuses: _farmerInTransitStatuses,
      );
    });

/// Completed / cancelled orders for a farmer.
final farmerHistoryOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, String>((ref, farmerProfileId) {
      return _orderService.watchOrdersForFarmer(
        farmerProfileId: farmerProfileId,
        statuses: _farmerHistoryStatuses,
      );
    });

// ---------------------------------------------------------------------------
// Driver providers
// ---------------------------------------------------------------------------

/// Deliveries the driver can pick up (assigned or packed orders).
final driverPickupRequestsProvider = StreamProvider.autoDispose
    .family<List<DeliverySummary>, String>((ref, driverProfileId) {
      return _orderService.watchDeliveriesForDriver(
        driverProfileId: driverProfileId,
        deliveryStatuses: _driverPickupStatuses,
      );
    });

/// Active deliveries the driver is currently moving.
final driverActiveDeliveriesProvider = StreamProvider.autoDispose
    .family<List<DeliverySummary>, String>((ref, driverProfileId) {
      return _orderService.watchDeliveriesForDriver(
        driverProfileId: driverProfileId,
        deliveryStatuses: _driverActiveStatuses,
      );
    });

/// Completed deliveries for the driver.
final driverCompletedDeliveriesProvider = StreamProvider.autoDispose
    .family<List<DeliverySummary>, String>((ref, driverProfileId) {
      return _orderService.watchDeliveriesForDriver(
        driverProfileId: driverProfileId,
        deliveryStatuses: _driverCompletedStatuses,
      );
    });

// ---------------------------------------------------------------------------
// Detail provider
// ---------------------------------------------------------------------------

/// Full detail for a single order — used by OrderDetailScreen.
final orderDetailProvider = StreamProvider.autoDispose
    .family<OrderDetail?, String>((ref, orderId) {
      return _orderService.watchOrderDetail(orderId);
    });
