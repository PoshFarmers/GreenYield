import 'package:flutter/material.dart';

import 'recurring_schedule_list_screen.dart';

class RecurringOrdersScreen extends StatelessWidget {
  final String buyerProfileId;

  const RecurringOrdersScreen({super.key, required this.buyerProfileId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Orders')),
      body: RecurringScheduleListWidget(buyerProfileId: buyerProfileId),
    );
  }
}
