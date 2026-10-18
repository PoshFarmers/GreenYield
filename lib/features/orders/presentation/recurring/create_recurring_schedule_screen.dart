import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local_db/powersync.dart';
import '../../../../core/supabase/client.dart';
import '../../../../core/widgets/app_secondary_header.dart';
import '../../../../core/widgets/avatar_image.dart';
import '../../../../core/widgets/media_image.dart';
import '../../../../models/marketplace_listing.dart';
import '../../../marketplace/marketplace_service.dart';
import 'recurring_messages.dart';

import 'package:greenyield/models/wallet.dart';
import 'package:greenyield/features/wallet/wallet_service.dart';
import 'package:greenyield/features/wallet/presentation/wallet_screen.dart';

import '../../recurring_order_models.dart';
import '../../recurring_order_service.dart';

class ScheduleItemState {
  final String cropId;
  final String cropName;
  final String imageUrl;
  final String? cropCategory;
  double quantity;
  String? preferredFarmerId;
  String? preferredFarmerName;
  double? preferredFarmerPrice;

  ScheduleItemState({
    required this.cropId,
    required this.cropName,
    required this.imageUrl,
    this.cropCategory,
    this.quantity = 1.0,
    this.preferredFarmerId,
    this.preferredFarmerName,
    this.preferredFarmerPrice,
  });
}

class CreateRecurringScheduleScreen extends ConsumerStatefulWidget {
  final String buyerProfileId;
  final String? existingScheduleId;

  const CreateRecurringScheduleScreen({
    super.key,
    required this.buyerProfileId,
    this.existingScheduleId,
  });

  @override
  ConsumerState<CreateRecurringScheduleScreen> createState() =>
      _CreateRecurringScheduleScreenState();
}

class _CreateRecurringScheduleScreenState
    extends ConsumerState<CreateRecurringScheduleScreen> {
  final _service = RecurringOrderService();
  final _marketplace = const MarketplaceService();
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();

  int _currentStep = 0;
  String _frequency = 'weekly';
  DateTime? _endDate;

  // Days of week (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
  final Set<int> _selectedDays = {};

  // Map of day index to list of items
  final Map<int, List<ScheduleItemState>> _itemsPerDay = {};

  bool _isSaving = false;
  bool _isLoading = true;

  String _resolveCropImageBucket(String? path) {
    if (path == null) return 'crop-photos';
    if (path.contains('crop-fallback') ||
        path.startsWith('crops/') ||
        !path.contains('/')) {
      return 'crop-fallback-images';
    }
    return 'crop-photos';
  }

  @override
  void initState() {
    super.initState();
    _loadExistingSchedule();
  }

  Future<void> _loadExistingSchedule() async {
    if (widget.existingScheduleId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Server reads: the local mirror of these tables is empty after a
      // re-login (the recurring sync streams are invalid).
      final scheduleId = widget.existingScheduleId!;
      final schedule = await supabase
          .from('recurring_schedule')
          .select('label, end_date')
          .eq('id', scheduleId)
          .maybeSingle();
      if (schedule == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _labelController.text = schedule['label'] as String;
      if (schedule['end_date'] != null) {
        _endDate = DateTime.parse(schedule['end_date'] as String).toLocal();
      }

      final days = await _service.fetchScheduleDays(scheduleId);
      if (days.isNotEmpty) {
        _frequency = days.first.frequency;
        _addressController.text =
            days.first.deliveryAddress?['line1']?.toString() ?? '';
      }

      // Preferred farmers' names/prices, one marketplace lookup per crop.
      final farmerInfo = <String, Map<String, dynamic>>{}; // crop:farmer
      final cropsWithPreferred = {
        for (final day in days)
          for (final item in day.items)
            if (item.preferredFarmerId != null) item.cropId: item.cropName,
      };
      for (final entry in cropsWithPreferred.entries) {
        try {
          for (final f in await _farmersForCrop(entry.key, entry.value)) {
            farmerInfo['${entry.key}:${f['id']}'] = f;
          }
        } catch (_) {
          // Name/price are cosmetic here; the choice itself is kept.
        }
      }

      for (final day in days) {
        _selectedDays.add(day.dayOfWeek);
        _itemsPerDay[day.dayOfWeek] = day.items.map((item) {
          final farmer = farmerInfo['${item.cropId}:${item.preferredFarmerId}'];
          return ScheduleItemState(
            cropId: item.cropId,
            cropName: item.cropName,
            imageUrl: item.fallbackImageUrl ?? '',
            cropCategory: item.cropCategory,
            quantity: item.quantityKg,
            preferredFarmerId: item.preferredFarmerId,
            preferredFarmerName: item.preferredFarmerId == null
                ? null
                : (farmer?['farmer_name'] as String? ?? 'Preferred farmer'),
            preferredFarmerPrice: (farmer?['price_per_kg'] as num?)?.toDouble(),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't load this schedule. Check your connection and try again.",
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep == 0) {
      if (_labelController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a schedule label.')),
        );
        return;
      }
    } else if (_currentStep == 1) {
      if (_selectedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one day.')),
        );
        return;
      }
      bool hasItems = false;
      for (final day in _selectedDays) {
        if ((_itemsPerDay[day] ?? []).isNotEmpty) {
          hasItems = true;
          break;
        }
      }
      if (!hasItems) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one item.')),
        );
        return;
      }
    } else if (_currentStep == 2) {
      if (_addressController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a delivery address.')),
        );
        return;
      }
      _saveSchedule();
      return;
    }
    setState(() => _currentStep += 1);
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    } else {
      Navigator.pop(context);
    }
  }

  /// One atomic server call. Next delivery dates are computed server-side
  /// (Asia/Colombo); if a chosen day is tomorrow, that order is placed
  /// right away and we say so.
  Future<void> _saveSchedule() async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _service.saveSchedule(
        scheduleId: widget.existingScheduleId,
        label: _labelController.text.trim(),
        frequency: _frequency,
        deliveryAddress: {'line1': _addressController.text.trim()},
        endDate: _endDate,
        itemsByDay: {
          for (final day in _selectedDays)
            day: [
              for (final item in _itemsPerDay[day] ?? <ScheduleItemState>[])
                RecurringItemInput(
                  cropId: item.cropId,
                  quantityKg: item.quantity,
                  preferredFarmerId: item.preferredFarmerId,
                ),
            ],
        },
      );

      if (result.problemReasons.isNotEmpty) {
        debugPrint(
          "Tomorrow's recurring order not placed: ${result.problemReasons}",
        );
      }
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(recurringTomorrowMessage(result.summary, saved: true)),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't save the schedule. Check your connection and try again.",
          ),
        ),
      );
      debugPrint('save_recurring_schedule failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppSecondaryHeader(
        title: widget.existingScheduleId != null
            ? 'Edit Schedule'
            : 'Create Schedule',
        // A close (not back) affordance: this is a dismissable flow, so
        // the X moves to the actions slot rather than becoming an arrow.
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepContinue: _next,
        onStepCancel: _back,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : details.onStepContinue,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _currentStep == 2 ? 'Confirm Schedule' : 'Continue',
                          ),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : details.onStepCancel,
                      child: const Text('Back'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Basics'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: _buildStep1(),
          ),
          Step(
            title: const Text('Days & Items'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: _buildStep2(),
          ),
          Step(
            title: const Text('Review'),
            isActive: _currentStep >= 2,
            content: _buildStep3(),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(
            labelText: 'Schedule Label',
            hintText: 'e.g. Weekly Veg Restock',
            prefixIcon: Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Frequency', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'weekly', label: Text('Weekly')),
            ButtonSegment(value: 'biweekly', label: Text('Bi-weekly')),
            ButtonSegment(value: 'monthly', label: Text('Monthly')),
          ],
          selected: {_frequency},
          onSelectionChanged: (val) {
            setState(() => _frequency = val.first);
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'End Date (Optional)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _endDate == null
                ? 'No end date (runs indefinitely)'
                : '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate:
                  _endDate ?? DateTime.now().add(const Duration(days: 30)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (date != null) {
              setState(() => _endDate = date);
            }
          },
        ),
        if (_endDate != null)
          TextButton(
            onPressed: () => setState(() => _endDate = null),
            child: const Text('Clear End Date'),
          ),
      ],
    );
  }

  Widget _buildStep2() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select delivery days',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(7, (i) {
            // Dart DateTime weekdays: 1=Mon, 7=Sun. In DB we use 0=Sun, 1=Mon ... 6=Sat for simplicity,
            // but let's align with dart: DateTime.monday = 1
            final dayValue = (i + 1) % 7; // This gives 1=Mon...6=Sat, 0=Sun
            final isSelected = _selectedDays.contains(dayValue);
            return FilterChip(
              label: Text(days[i]),
              selected: isSelected,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedDays.add(dayValue);
                  } else {
                    _selectedDays.remove(dayValue);
                  }
                });
              },
            );
          }),
        ),
        const SizedBox(height: 24),
        if (_selectedDays.isEmpty)
          const Text(
            'Select a day above to add items.',
            style: TextStyle(color: Colors.grey),
          ),
        ...(_selectedDays.toList()..sort()).map((day) {
          final dayName = const [
            'Sun',
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
          ][day];
          final items = _itemsPerDay[day] ?? [];
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  '$dayName Items',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${items.length} crops'),
                initiallyExpanded: true,
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No items added for this day.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ...items.map((item) {
                    final isFruit = item.cropCategory?.toLowerCase() == 'fruit';
                    final categoryIcon = Icon(
                      isFruit ? Icons.apple : Icons.eco,
                      size: 24,
                      color: theme.colorScheme.primary,
                    );

                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: MediaImage(
                            path: item.imageUrl,
                            bucket: _resolveCropImageBucket(item.imageUrl),
                            public: true,
                            placeholder: Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                              alignment: Alignment.center,
                              child: categoryIcon,
                            ),
                          ),
                        ),
                      ),
                      title: Text(item.cropName),
                      subtitle: item.preferredFarmerName != null
                          ? Text(
                              'Prefers: ${item.preferredFarmerName}',
                              style: const TextStyle(color: Colors.blue),
                            )
                          : const Text(
                              'Auto-match farmer',
                              style: TextStyle(color: Colors.grey),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${item.quantity} kg',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _itemsPerDay[day]!.remove(item);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: OutlinedButton.icon(
                      onPressed: () => _showCropPicker(day),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Crop'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3() {
    final theme = Theme.of(context);
    double estimatedCost = 0;

    // Calculate simple estimate if preferred prices exist
    for (final day in _selectedDays) {
      for (final item in _itemsPerDay[day] ?? []) {
        estimatedCost += (item.preferredFarmerPrice ?? 200.0) * item.quantity;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _addressController,
          decoration: const InputDecoration(
            labelText: 'Delivery Address',
            hintText: 'Enter full delivery address',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Estimated Cost per occurrence'),
                  Text(
                    'Rs ${estimatedCost.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Estimated — actual price may vary based on farmer prices at the time of delivery.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Wallet Balance',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<Wallet?>(
                stream: const WalletService().watchBalance(
                  widget.buyerProfileId,
                ),
                builder: (context, snapshot) {
                  final wallet = snapshot.data;
                  final text = wallet == null
                      ? 'LKR 0.00'
                      : '${wallet.currency} ${wallet.balance.toStringAsFixed(2)}';
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WalletScreen(
                                profileId: widget.buyerProfileId,
                              ),
                            ),
                          );
                        },
                        child: const Text('Top Up'),
                      ),
                    ],
                  );
                },
              ),
              const Divider(),
              const Text(
                'Recurring orders are paid automatically from your GreenYield Wallet on each scheduled date. Make sure your wallet balance is topped up.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCropPicker(int day) async {
    final crops = await db.getAll('SELECT * FROM crop ORDER BY name ASC');

    if (!mounted) return;
    // ignore: unawaited_futures
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return FractionallySizedBox(
          heightFactor: 0.8,
          child: Column(
            children: [
              AppSecondaryHeader(
                title: 'Select Crop',
                showBackButton: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: crops.length,
                  itemBuilder: (context, index) {
                    final crop = crops[index];
                    final fallbackUrl = crop['fallback_image_url'] as String?;
                    final category = crop['category'] as String?;
                    final isFruit = category?.toLowerCase() == 'fruit';
                    final categoryIcon = Icon(
                      isFruit ? Icons.apple : Icons.eco,
                      size: 24,
                      color: theme.colorScheme.primary,
                    );

                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: MediaImage(
                            path: fallbackUrl,
                            bucket: _resolveCropImageBucket(fallbackUrl),
                            public: true,
                            placeholder: Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                              alignment: Alignment.center,
                              child: categoryIcon,
                            ),
                          ),
                        ),
                      ),
                      title: Text(crop['name'] as String),
                      onTap: () {
                        Navigator.pop(context);
                        _showQuantityAndFarmerPicker(
                          day,
                          crop['id'] as String,
                          crop['name'] as String,
                          fallbackUrl ?? '',
                          category,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQuantityAndFarmerPicker(
    int day,
    String cropId,
    String cropName,
    String imageUrl, [
    String? cropCategory,
  ]) {
    final quantityController = TextEditingController(text: '1');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String? pickedFarmerId;
        String? pickedFarmerName;
        double? pickedFarmerPrice;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add $cropName',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity (kg)',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Preferred Farmer',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  // Show current selection
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: pickedFarmerId == null
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      border: Border.all(
                        color: pickedFarmerId == null
                            ? Colors.green
                            : Colors.blue,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          pickedFarmerId == null
                              ? Icons.auto_awesome
                              : Icons.person,
                          color: pickedFarmerId == null
                              ? Colors.green
                              : Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            pickedFarmerId == null
                                ? 'Auto-match: Cheapest & Closest'
                                : '$pickedFarmerName  •  LKR $pickedFarmerPrice/kg',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setSheetState(() {
                              pickedFarmerId = null;
                              pickedFarmerName = null;
                              pickedFarmerPrice = null;
                            });
                          },
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Auto-match'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final selected = await _showFarmerPicker(
                              cropId,
                              cropName,
                            );
                            if (selected != null && selected.isNotEmpty) {
                              setSheetState(() {
                                pickedFarmerId = selected['id'] as String;
                                pickedFarmerName = selected['name'] as String;
                                pickedFarmerPrice = (selected['price'] as num)
                                    .toDouble();
                              });
                            }
                          },
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text('Choose Farmer'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final qty =
                            double.tryParse(quantityController.text) ?? 1.0;
                        setState(() {
                          _itemsPerDay
                              .putIfAbsent(day, () => [])
                              .add(
                                ScheduleItemState(
                                  cropId: cropId,
                                  cropName: cropName,
                                  imageUrl: imageUrl,
                                  cropCategory: cropCategory,
                                  quantity: qty,
                                  preferredFarmerId: pickedFarmerId,
                                  preferredFarmerName: pickedFarmerName,
                                  preferredFarmerPrice: pickedFarmerPrice,
                                ),
                              );
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('Add to Schedule'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Farmers currently selling [cropId], one row per farmer (their
  /// best-stocked listing). Server-side via the marketplace search: other
  /// users' profiles don't sync locally, and the local listing column is
  /// `status_text`, so the old local query returned nothing.
  Future<List<Map<String, dynamic>>> _farmersForCrop(
    String cropId,
    String cropName,
  ) async {
    final listings = await _marketplace.search(query: cropName, limit: 50);
    final byFarmer = <String, MarketplaceListing>{};
    for (final l in listings) {
      if (l.cropId != cropId || l.isSoldOut) continue;
      final best = byFarmer[l.farmerProfileId];
      if (best == null || l.availableQuantityKg > best.availableQuantityKg) {
        byFarmer[l.farmerProfileId] = l;
      }
    }
    final rows = byFarmer.values.toList()
      ..sort((a, b) {
        final byStock = b.availableQuantityKg.compareTo(a.availableQuantityKg);
        return byStock != 0 ? byStock : a.pricePerKg.compareTo(b.pricePerKg);
      });
    return [
      for (final l in rows)
        {
          'id': l.farmerProfileId,
          'farmer_name': l.farmerName.isEmpty ? 'Farmer' : l.farmerName,
          'price_per_kg': l.pricePerKg,
          'available_quantity_kg': l.availableQuantityKg,
          'avatar_url': l.farmerAvatarUrl,
        },
    ];
  }

  Future<Map<String, dynamic>?> _showFarmerPicker(
    String cropId,
    String cropName,
  ) async {
    List<Map<String, dynamic>> farmers;
    try {
      farmers = await _farmersForCrop(cropId, cropName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't load farmers. Check your connection and try again.",
            ),
          ),
        );
      }
      return null;
    }

    if (!mounted) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredFarmers = farmers.where((f) {
              final name = (f['farmer_name'] as String? ?? '').toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            return FractionallySizedBox(
              heightFactor: 0.8,
              child: Column(
                children: [
                  AppSecondaryHeader(
                    title: 'Select Preferred Farmer',
                    showBackButton: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search Farmers',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.auto_awesome,
                      color: Colors.green,
                    ),
                    title: const Text('Auto-match best available'),
                    subtitle: const Text('System will pick cheapest & closest'),
                    onTap: () =>
                        Navigator.pop(context, {}), // Empty map for auto-match
                  ),
                  const Divider(),
                  if (filteredFarmers.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No farmers match your search.'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredFarmers.length,
                        itemBuilder: (context, index) {
                          final f = filteredFarmers[index];
                          return ListTile(
                            // avatar_url is a storage path, not a URL —
                            // AvatarImage resolves it (NetworkImage can't).
                            leading: AvatarImage(
                              path: f['avatar_url'] as String?,
                              radius: 20,
                            ),
                            title: Text(
                              f['farmer_name'] as String? ?? 'Farmer',
                            ),
                            trailing: Text(
                              'LKR ${f['price_per_kg']}/kg\n'
                              '${f['available_quantity_kg']} kg available',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context, {
                                'id': f['id'] as String,
                                'name': f['farmer_name'] as String? ?? 'Farmer',
                                'price': f['price_per_kg'],
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
