// The single combined vehicle+routes form has been replaced by the
// two-step `DriverRegistrationFlow` wizard (Vehicle Details, then
// Preferred Route), matching the updated onboarding designs. This file
// stays around only so existing imports/registrations don't need to
// change; new code should import driver_registration_flow.dart directly.
export 'driver_registration_flow.dart' show DriverRegistrationFlow;

import 'driver_registration_flow.dart';

typedef DriverCompleteProfileScreen = DriverRegistrationFlow;
