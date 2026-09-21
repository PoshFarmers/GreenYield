import 'package:flutter/material.dart';

import '../../../../core/widgets/app_secondary_header.dart';
import 'recurring_schedule_list_screen.dart';

class RecurringOrdersScreen extends StatelessWidget {
  final String buyerProfileId;

  const RecurringOrdersScreen({super.key, required this.buyerProfileId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppSecondaryHeader(title: 'Recurring Orders'),
      body: RecurringScheduleListWidget(buyerProfileId: buyerProfileId),
    );
  }
}
