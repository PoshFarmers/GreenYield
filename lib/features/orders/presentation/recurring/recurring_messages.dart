import 'package:flutter/material.dart';

import '../../recurring_order_models.dart';
import '../../recurring_order_service.dart';

/// Pause or resume [scheduleId] on the server and tell the buyer what
/// happened. Shared by the schedule list menu and the detail screen.
Future<void> setScheduleActiveWithFeedback(
  BuildContext context,
  RecurringOrderService service,
  String scheduleId, {
  required bool active,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await service.setScheduleStatus(scheduleId, active: active);
    if (result.problemReasons.isNotEmpty) {
      debugPrint(
        "Tomorrow's recurring order not placed: ${result.problemReasons}",
      );
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          active ? recurringTomorrowMessage(result.summary, saved: false) : 'Schedule paused. No orders will be placed until you resume it.',
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't update the schedule. Check your connection and try again.",
        ),
      ),
    );
  }
}

/// Feedback after saving or resuming a schedule, so the buyer knows
/// whether tomorrow's delivery was placed right away (and if not, why).
/// [saved]: true after create/edit, false after resume.
String recurringTomorrowMessage(
  TomorrowSummary summary, {
  required bool saved,
}) {
  final lead = saved ? 'Schedule saved.' : 'Schedule resumed.';
  return switch (summary) {
    TomorrowSummary.none => lead,
    TomorrowSummary.placed =>
      "$lead Tomorrow's order has been placed. You'll find it in Active Orders.",
    TomorrowSummary.needsFunds =>
      "$lead Tomorrow's order is waiting for wallet funds. Top up and it will "
          'be placed automatically within the hour.',
    TomorrowSummary.needsStock =>
      "$lead Tomorrow's order is waiting for stock. We'll keep trying and "
          'notify you.',
    TomorrowSummary.ended =>
      "$lead The end date is before tomorrow, so the schedule has ended and "
          'no order was placed. Edit it and choose a later end date to '
          'continue.',
    TomorrowSummary.failed =>
      "$lead Tomorrow's order couldn't be placed right now. We'll retry "
          'automatically.',
  };
}
