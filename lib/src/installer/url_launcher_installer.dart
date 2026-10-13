import 'package:url_launcher/url_launcher.dart';
import '../model/platform_target.dart';
import 'app_installer.dart';

typedef UrlLaunchHandler = Future<bool> Function(
  Uri url, {
  LaunchMode mode,
});

/// Installer for store/web redirects (iOS App Store, TestFlight, Google Play, etc.).
class UrlLauncherInstaller implements AppInstaller {
  final UrlLaunchHandler _launchHandler;

  UrlLauncherInstaller({UrlLaunchHandler? launchHandler})
      : _launchHandler = launchHandler ?? launchUrl;

  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    final uri = Uri.tryParse(target.url);
    if (uri == null) {
      return false;
    }

    return _launchHandler(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}
