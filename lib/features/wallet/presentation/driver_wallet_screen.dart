import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/role_bottom_nav_bar.dart';
import '../../../models/profile.dart';
import '../../../models/wallet_snapshot.dart';

/// Driver's "My Wallet" screen — balance, recent payout status, linked
/// bank, and recent activity. Mirrors Driver_Wallet.png.
///
/// Reached by pushing this screen (e.g. from the "View" link on the
/// driver profile's wallet card), so the header here is a standard
/// back+title+help [AppBar] — the same pattern every other pushed
/// driver screen uses (see `DriverManageRoutesScreen`), not the
/// tab-root `AppHeader` with the bell/avatar. Since this screen lives
/// outside `AppNavShell`'s `IndexedStack`, it supplies its own
/// [RoleBottomNavBar] so the app's standard footer still shows here —
/// tapping a destination hands control back to the shell.
///
/// Only "Withdraw" is offered per spec (no "Add Money" for drivers —
/// money arrives via delivery-fee payouts, not top-ups). Data is
/// placeholder ([sampleWalletSnapshot]) until a real wallet
/// provider exists — see that file's doc comment for the swap-in plan.
class DriverWalletScreen extends StatelessWidget {
  final Profile profile;

  const DriverWalletScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width < 600 ? width : 560.0;
    final hPad = width < 360 ? 12.0 : 16.0;
    final snapshot = sampleWalletSnapshot();

    return Scaffold(
      appBar: AppBar(
        title: Text('my_wallet'.tr()),
        actions: [
          IconButton(
            tooltip: 'help'.tr(),
            icon: const Icon(Icons.help_outline),
            onPressed: () {},
          ),
        ],
      ),
      bottomNavigationBar: RoleBottomNavBar(
        role: profile.activeRole ?? 'driver',
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
              children: [
                _BalanceCard(balance: snapshot.availableBalance),
                const SizedBox(height: 16),
                _RecentPayoutCard(
                  amount: snapshot.recentPayoutAmount,
                  expectedArrival: snapshot.recentPayoutExpectedArrival,
                ),
                const SizedBox(height: 16),
                _LinkedBankCard(
                  bankName: snapshot.bankName,
                  last4: snapshot.bankAccountLast4,
                ),
                const SizedBox(height: 24),
                Text(
                  'recent_activity'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _RecentActivityCard(transactions: snapshot.recentActivity),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () {},
                    child: Text('view_all_transactions'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formats a whole-rupee amount with thousands separators, e.g. 28400
/// -> "28,400". Written by hand rather than pulling in `intl`'s
/// `NumberFormat`, matching this screen's siblings (see
/// `driver_calendar_screen.dart`), which avoid a direct `intl` import
/// since it's only a transitive dependency here (via easy_localization).
String _formatAmount(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-${buffer.toString()}' : buffer.toString();
}

class _BalanceCard extends StatelessWidget {
  final int balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_balance_wallet,
              color: theme.colorScheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'available_balance'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'LKR ${_formatAmount(balance)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: ElevatedButton(
              onPressed: () {},
              child: Text('withdraw'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPayoutCard extends StatelessWidget {
  final int amount;
  final DateTime expectedArrival;

  const _RecentPayoutCard({
    required this.amount,
    required this.expectedArrival,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = TimeOfDay.fromDateTime(expectedArrival).format(context);
    final dayLabel = _isTomorrow(expectedArrival)
        ? 'tomorrow'.tr()
        : '${expectedArrival.day}/${expectedArrival.month}/${expectedArrival.year}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'recent_payout'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const _ProcessingPill(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Rs. ${_formatAmount(amount)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'expected_arrival'.tr(
                namedArgs: {'day': dayLabel, 'time': timeLabel},
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isTomorrow(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day;
  }
}

class _ProcessingPill extends StatelessWidget {
  const _ProcessingPill();

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFC107);
    const amberText = Color(0xFFB8860B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.autorenew, size: 13, color: amberText),
          const SizedBox(width: 4),
          Text(
            'processing'.tr(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: amberText,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedBankCard extends StatelessWidget {
  final String bankName;
  final String last4;

  const _LinkedBankCard({required this.bankName, required this.last4});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'linked_bank'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('manage'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.account_balance_outlined,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bankName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'account_ending'.tr(namedArgs: {'last4': last4}),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final List<WalletTransaction> transactions;

  const _RecentActivityCard({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < transactions.length; i++) ...[
            _TransactionRow(transaction: transactions[i]),
            if (i != transactions.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionRow({required this.transaction});

  String _relativeDate(DateTime date) {
    final today = DateTime.now();
    final diff = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (diff == 0) return 'today'.tr();
    if (diff == 1) return 'yesterday'.tr();
    return 'days_ago'.tr(namedArgs: {'count': '$diff'});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDelivery = transaction.type == WalletTransactionType.deliveryFee;
    final positive = transaction.amount >= 0;
    final dateLabel = _relativeDate(transaction.date);
    final subtitle = transaction.orderRef != null
        ? '${'order_ref'.tr(namedArgs: {'id': transaction.orderRef!})} \u2022 $dateLabel'
        : dateLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              isDelivery ? Icons.local_shipping_outlined : Icons.north,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDelivery ? 'delivery_fee'.tr() : 'payout_to_bank'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${positive ? '+' : '-'} LKR ${_formatAmount(transaction.amount.abs())}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: positive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
