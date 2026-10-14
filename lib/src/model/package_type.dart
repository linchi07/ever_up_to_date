/// Package distribution format and installation strategy.
enum PackageType {
  directApk,
  googlePlay,
  innoSetup,
  genericInstaller,
  portableArchive,
  appStore,
  testflight,
  dmg,
  pkg,
  appImage,
  custom;

  /// Canonical JSON protocol spelling.
  String get key => switch (this) {
    directApk => 'direct_apk',
    googlePlay => 'google_play',
    innoSetup => 'inno_setup',
    genericInstaller => 'generic_installer',
    portableArchive => 'portable_archive',
    appStore => 'app_store',
    appImage => 'app_image',
    _ => name,
  };

  static PackageType fromString(String name) {
    switch (name.toLowerCase()) {
      case 'direct_apk':
      case 'directapk':
      case 'apk':
        return PackageType.directApk;
      case 'google_play':
      case 'googleplay':
      case 'play':
        return PackageType.googlePlay;
      case 'inno_setup':
      case 'innosetup':
        return PackageType.innoSetup;
      case 'generic_installer':
      case 'installer':
        return PackageType.genericInstaller;
      case 'portable_archive':
      case 'zip':
      case 'portable':
        return PackageType.portableArchive;
      case 'app_store':
      case 'appstore':
        return PackageType.appStore;
      case 'testflight':
        return PackageType.testflight;
      case 'dmg':
        return PackageType.dmg;
      case 'pkg':
        return PackageType.pkg;
      case 'app_image':
      case 'appimage':
        return PackageType.appImage;
      default:
        return PackageType.custom;
    }
  }

  /// Whether this package type requires downloading a binary file locally.
  bool get isDirectDownload {
    switch (this) {
      case PackageType.directApk:
      case PackageType.innoSetup:
      case PackageType.genericInstaller:
      case PackageType.portableArchive:
      case PackageType.dmg:
      case PackageType.pkg:
      case PackageType.appImage:
      case PackageType.custom:
        return true;
      case PackageType.googlePlay:
      case PackageType.appStore:
      case PackageType.testflight:
        return false;
    }
  }

  /// Whether this package type guides user to external store or portal.
  bool get isExternalStore {
    return !isDirectDownload;
  }
}
