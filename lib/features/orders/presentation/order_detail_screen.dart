import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../order_providers.dart';
import '../order_service.dart';
import '../order_detail_models.dart';
import 'widgets/info_card.dart';
import 'widgets/order_item_card.dart';
import 'widgets/order_status_chip.dart';
import 'widgets/order_stepper.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String viewerRole; // 'buyer', 'farmer', 'driver'

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    required this.viewerRole,
  });

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  final _service = const OrderService();
  bool _isLoadingAction = false;

  Future<void> _handleAction(Future<void> Function() action) async {
    setState(() => _isLoadingAction = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(orderDetailProvider(widget.orderId));

    return Scaffold(
      appBar: const AppSecondaryHeader(
        title: 'Order Details',
        showBackButton: true,
      ),
      body: asyncDetail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Order not found.'));
          }
          return _buildContent(context, detail);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, OrderDetail detail) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            // Status and ID
            Row(
              children: [
                Expanded(
                  child: Text(
                    detail.displayId,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OrderStatusChip(status: detail.status, fontSize: 13),
              ],
            ),
            const SizedBox(height: 8),

            // Date
            Text(
              detail.orderDate != null
                  ? 'Requested Delivery: ${DateFormat('MMM d, yyyy').format(detail.orderDate!)}'
                  : 'Placed: ${DateFormat('MMM d, yyyy').format(detail.placedAt)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Stepper
            OrderStepper(currentStep: detail.stepperIndex),
            const SizedBox(height: 32),

            // Role-specific sections
            if (widget.viewerRole == 'buyer') _buildBuyerSections(detail),
            if (widget.viewerRole == 'farmer') _buildFarmerSections(detail),
            if (widget.viewerRole == 'driver') _buildDriverSections(detail),
            const SizedBox(height: 24),

            // Items
            _buildSectionHeader('Items'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: detail.items
                    .map((item) => OrderItemCard(item: item))
                    .toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Summary
            _buildSectionHeader('Order Summary'),
            const SizedBox(height: 12),
            _buildSummaryCard(context, detail),
          ],
        ),

        // Bottom Action Bar
        if (_hasActions(detail))
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildActionBar(context, detail),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Role Sections
  // ---------------------------------------------------------------------------

  Widget _buildBuyerSections(OrderDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          sectionLabel: 'Farmer Details',
          leadingIcon: Icons.storefront_outlined,
          title: detail.farmerName,
          phone: detail.farmerPhone,
          address: detail.farmerAddress,
          extraAction: ChatActionButton(id: 'chat_farmer', onTap: () {}),
        ),
        if (detail.driverProfileId != null) ...[
          const SizedBox(height: 20),
          InfoCard(
            sectionLabel: 'Driver Details',
            leadingIcon: Icons.local_shipping_outlined,
            title: detail.driverName ?? 'Driver Assigned',
            phone: detail.driverPhone,
            subtitle:
                '${detail.vehicleType ?? 'Vehicle'} • ${detail.vehiclePlate ?? ''}',
            extraAction: ChatActionButton(id: 'chat_driver', onTap: () {}),
          ),
        ] else if (detail.status == OrderStatus.placed ||
            detail.status == OrderStatus.confirmed) ...[
          const SizedBox(height: 20),
          const InfoCard(
            sectionLabel: 'Delivery',
            leadingIcon: Icons.schedule_outlined,
            title: 'Assigning Driver',
            subtitle: 'We are locating the nearest driver for your order.',
          ),
        ],
      ],
    );
  }

  Widget _buildFarmerSections(OrderDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          sectionLabel: 'Buyer Details',
          leadingIcon: Icons.person_outlined,
          title: detail.buyerName,
          phone: detail.buyerPhone,
          extraAction: ChatActionButton(id: 'chat_buyer', onTap: () {}),
        ),
        if (detail.driverProfileId != null) ...[
          const SizedBox(height: 20),
          InfoCard(
            sectionLabel: 'Driver Details',
            leadingIcon: Icons.local_shipping_outlined,
            title: detail.driverName ?? 'Driver Assigned',
            phone: detail.driverPhone,
            subtitle:
                '${detail.vehicleType ?? 'Vehicle'} • ${detail.vehiclePlate ?? ''}',
            extraAction: ChatActionButton(id: 'chat_driver', onTap: () {}),
          ),
        ],
      ],
    );
  }

  Widget _buildDriverSections(OrderDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(
          sectionLabel: 'Pickup Details',
          leadingIcon: Icons.storefront_outlined,
          title: detail.farmerName,
          phone: detail.farmerPhone,
          address: detail.farmerAddress,
          extraAction: ChatActionButton(id: 'chat_farmer', onTap: () {}),
        ),
        const SizedBox(height: 20),
        InfoCard(
          sectionLabel: 'Dropoff Details',
          leadingIcon: Icons.person_outlined,
          title: detail.buyerName,
          phone: detail.buyerPhone,
          address: detail.buyerAddress,
          extraAction: ChatActionButton(id: 'chat_buyer', onTap: () {}),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Action Bar
  // ---------------------------------------------------------------------------

  bool _hasActions(OrderDetail detail) {
    if (widget.viewerRole == 'farmer' &&
        (detail.status == OrderStatus.assigned ||
            detail.status == OrderStatus.confirmed)) {
      return true;
    }
    if (widget.viewerRole == 'driver') {
      if (detail.status == OrderStatus.packed) return true;
      if (detail.status == OrderStatus.pickedUp ||
          detail.status == OrderStatus.inTransit) {
        return true;
      }
    }
    if ((widget.viewerRole == 'buyer' || widget.viewerRole == 'driver') &&
        detail.status.isCancellable) {
      return true; // We'll show cancel in a secondary menu or button.
    }
    return false;
  }

  Widget _buildActionBar(BuildContext context, OrderDetail detail) {
    final theme = Theme.of(context);
    Widget primaryButton = const SizedBox();
    Widget? secondaryButton;

    if (widget.viewerRole == 'farmer' &&
        (detail.status == OrderStatus.assigned ||
            detail.status == OrderStatus.confirmed)) {
      primaryButton = FilledButton.icon(
        onPressed: _isLoadingAction
            ? null
            : () => _handleAction(() => _service.markOrderPacked(detail.id)),
        icon: const Icon(Icons.inventory_2),
        label: const Text('Mark as Packed'),
      );
    }

    if (widget.viewerRole == 'driver') {
      if (detail.status == OrderStatus.packed && detail.deliveryId != null) {
        primaryButton = FilledButton.icon(
          onPressed: _isLoadingAction
              ? null
              : () => _handleAction(
                  () => _service.confirmPickup(detail.deliveryId!),
                ),
          icon: const Icon(Icons.local_shipping),
          label: const Text('Confirm Pickup'),
        );
      } else if ((detail.status == OrderStatus.pickedUp ||
              detail.status == OrderStatus.inTransit) &&
          detail.deliveryId != null) {
        primaryButton = FilledButton.icon(
          onPressed: _isLoadingAction
              ? null
              : () => _handleAction(
                  () => _service.markDelivered(detail.deliveryId!),
                ),
          icon: const Icon(Icons.check_circle),
          label: const Text('Mark as Delivered'),
        );
      }
    }

    if ((widget.viewerRole == 'buyer' || widget.viewerRole == 'driver') &&
        detail.status.isCancellable) {
      secondaryButton = TextButton(
        onPressed: _isLoadingAction
            ? null
            : () => _handleAction(() => _service.cancelOrder(detail.id)),
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        child: const Text('Cancel Order'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (secondaryButton != null) ...[
              secondaryButton,
              const SizedBox(width: 16),
            ],
            Expanded(child: SizedBox(height: 48, child: primaryButton)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildSummaryCard(BuildContext context, OrderDetail detail) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Subtotal',
            value: 'LKR ${detail.subtotalAmount.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Delivery Fee',
            value: 'LKR ${detail.deliveryFeeAmount.toStringAsFixed(2)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'LKR ${detail.totalAmount.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
