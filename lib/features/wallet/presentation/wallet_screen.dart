import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../../models/wallet.dart';
import '../../payments/presentation/payment_methods_screen.dart';
import '../wallet_history.dart';
import '../wallet_service.dart';
import 'top_up_screen.dart';
import 'wallet_transaction_detail_screen.dart';
import 'withdraw_screen.dart';
import 'withdrawal_history_screen.dart';

/// Shared wallet screen for any role: live balance, Top up / Withdraw / Cards,
/// this-month summary and a filterable, date-grouped, infinitely scrolling
/// transaction list (all from the local mirror, so it works offline).
class WalletScreen extends StatefulWidget {
  final String profileId;

  const WalletScreen({super.key, required this.profileId});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const _pageSize = 30;

  final _service = const WalletService();
  final _history = const WalletHistoryService();
  final _scroll = ScrollController();

  late final Stream<Wallet?> _balance;
  late final Stream<WalletMonthSummary> _month;
  late Stream<List<WalletTransaction>> _txns;

  WalletFilter _filter = WalletFilter.all;
  int _limit = _pageSize;
  int _loaded = 0;
  List<WalletTransaction>? _last;

  @override
  void initState() {
    super.initState();
    _balance = _service.watchBalance(widget.profileId);
    _month = _history.watchMonthSummary(widget.profileId);
    _bind();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _bind() {
    _txns = _history.watchTransactions(
      widget.profileId,
      filter: _filter,
      limit: _limit,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // `_loaded >= _limit` means the last page was full, so there may be more.
    if (p.pixels >= p.maxScrollExtent - 300 && _loaded >= _limit) {
      setState(() {
        _limit += _pageSize;
        _bind();
      });
    }
  }

  void _setFilter(WalletFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _limit = _pageSize;
      _loaded = 0;
      _last = null;
      _bind();
    });
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'payments_wallet_today'.tr();
    if (diff == 1) return 'payments_wallet_yesterday'.tr();
    return DateFormat.yMMMd(context.locale.toString()).format(d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppSecondaryHeader(title: 'wallet_title'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                _balanceCard(theme),
                const SizedBox(height: 12),
                _monthSummary(theme),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _push(const WithdrawalHistoryScreen()),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text('payments_withdraw_history'.tr()),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'recent_transactions'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in WalletFilter.values) ...[
                        ChoiceChip(
                          label: Text(f.labelKey.tr()),
                          selected: _filter == f,
                          onSelected: (_) => _setFilter(f),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<WalletTransaction>>(
                  stream: _txns,
                  builder: (context, snapshot) {
                    final txns = snapshot.data ?? _last;
                    if (snapshot.data != null) {
                      _last = snapshot.data;
                      _loaded = snapshot.data!.length;
                    }
                    return _list(theme, txns);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'current_balance'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          StreamBuilder<Wallet?>(
            stream: _balance,
            builder: (context, snapshot) => Text(
              walletMoney(snapshot.data?.balance ?? 0),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _push(const TopUpScreen()),
                  icon: const Icon(Icons.add),
                  label: Text('top_up'.tr()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _push(WithdrawScreen(profileId: widget.profileId)),
                  icon: const Icon(Icons.arrow_upward),
                  label: Text('payments_withdraw_button'.tr()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _push(const PaymentMethodsScreen()),
              icon: const Icon(Icons.credit_card_outlined),
              label: Text('payments_wallet_cards'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthSummary(ThemeData theme) {
    return StreamBuilder<WalletMonthSummary>(
      stream: _month,
      builder: (context, snapshot) {
        final s = snapshot.data ?? const WalletMonthSummary();
        Widget tile(String key, double v, IconData icon, Color color) =>
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            key.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      walletMoney(v),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
        return Row(
          children: [
            tile(
              'payments_wallet_month_in',
              s.moneyIn,
              Icons.south_west,
              theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            tile(
              'payments_wallet_month_out',
              s.moneyOut,
              Icons.north_east,
              theme.colorScheme.error,
            ),
          ],
        );
      },
    );
  }

  Widget _list(ThemeData theme, List<WalletTransaction>? txns) {
    if (txns == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (txns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              (_filter == WalletFilter.all
                      ? 'no_transactions_yet'
                      : 'payments_wallet_empty_filter')
                  .tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    DateTime? currentDay;
    for (final t in txns) {
      final local = t.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (currentDay != day) {
        currentDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(
              _dayLabel(day),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      children.add(
        _TxnTile(
          transaction: t,
          onTap: () => _push(WalletTransactionDetailScreen(transaction: t)),
        ),
      );
    }
    if (_loaded >= _limit) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return Column(children: children);
  }
}

class _TxnTile extends StatelessWidget {
  final WalletTransaction transaction;
  final VoidCallback onTap;

  const _TxnTile({required this.transaction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = transaction;
    final isCredit = t.amount >= 0;
    final color = isCredit
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    final amount = NumberFormat('#,##0.00').format(t.amount.abs());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                walletTxnIcon(t),
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    walletTxnTitle(t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    DateFormat.jm(context.locale.toString())
                        .format(t.createdAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isCredit ? '+' : '-'}$amount',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
