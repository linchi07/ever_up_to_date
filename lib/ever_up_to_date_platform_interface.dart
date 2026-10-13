import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ever_up_to_date_method_channel.dart';

abstract class EverUpToDatePlatform extends PlatformInterface {
  /// Constructs a EverUpToDatePlatform.
  EverUpToDatePlatform() : super(token: _token);

  static final Object _token = Object();

  static EverUpToDatePlatform _instance = MethodChannelEverUpToDate();

  /// The default instance of [EverUpToDatePlatform] to use.
  ///
  /// Defaults to [MethodChannelEverUpToDate].
  static EverUpToDatePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EverUpToDatePlatform] when
  /// they register themselves.
  static set instance(EverUpToDatePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
