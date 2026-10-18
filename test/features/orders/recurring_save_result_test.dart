import 'package:flutter_test/flutter_test.dart';
import 'package:greenyield/features/orders/recurring_order_models.dart';

RecurringSaveResult _result(List<Map<String, dynamic>> tomorrow) =>
    RecurringSaveResult.fromMap({'schedule_id': 's1', 'tomorrow': tomorrow});

void main() {
  group('RecurringSaveResult.summary', () {
    test('no delivery tomorrow', () {
      expect(_result([]).summary, TomorrowSummary.none);
    });

    test('placed', () {
      expect(
        _result([
          {'day_of_week': 6, 'status': 'fulfilled'},
        ]).summary,
        TomorrowSummary.placed,
      );
    });

    test('already placed earlier counts as placed', () {
      expect(
        _result([
          {
            'day_of_week': 6,
            'status': 'skipped',
            'reason': 'already_processed',
          },
        ]).summary,
        TomorrowSummary.placed,
      );
    });

    test('waiting for funds wins over anything else', () {
      expect(
        _result([
          {'day_of_week': 6, 'status': 'fulfilled'},
          {'day_of_week': 6, 'status': 'awaiting_inventory'},
          {'day_of_week': 6, 'status': 'awaiting_funds'},
        ]).summary,
        TomorrowSummary.needsFunds,
      );
    });

    test('waiting for stock', () {
      expect(
        _result([
          {'day_of_week': 6, 'status': 'awaiting_inventory'},
        ]).summary,
        TomorrowSummary.needsStock,
      );
    });

    test('schedule ended before tomorrow is not reported as "will retry"', () {
      final result = _result([
        {'day_of_week': 6, 'status': 'skipped', 'reason': 'schedule_expired'},
      ]);
      expect(result.summary, TomorrowSummary.ended);
      expect(result.problemReasons, ['skipped: schedule_expired']);
    });

    test('errors are reported as failed', () {
      expect(
        _result([
          {'day_of_week': 6, 'status': 'error', 'reason': 'boom'},
        ]).summary,
        TomorrowSummary.failed,
      );
    });
  });
}
