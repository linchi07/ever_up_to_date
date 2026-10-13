import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ever_up_to_date_platform_interface.dart';

/// An implementation of [EverUpToDatePlatform] that uses method channels.
class MethodChannelEverUpToDate extends EverUpToDatePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ever_up_to_date');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
