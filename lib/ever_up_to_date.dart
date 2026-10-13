
import 'ever_up_to_date_platform_interface.dart';

class EverUpToDate {
  Future<String?> getPlatformVersion() {
    return EverUpToDatePlatform.instance.getPlatformVersion();
  }
}
