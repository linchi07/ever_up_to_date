/// Target operating system platform.
enum TargetPlatformType {
  android,
  windows,
  ios,
  macos,
  linux,
  web,
  unknown;

  static TargetPlatformType fromString(String name) {
    switch (name.toLowerCase()) {
      case 'android':
        return TargetPlatformType.android;
      case 'windows':
      case 'win':
        return TargetPlatformType.windows;
      case 'ios':
        return TargetPlatformType.ios;
      case 'macos':
      case 'darwin':
      case 'osx':
        return TargetPlatformType.macos;
      case 'linux':
        return TargetPlatformType.linux;
      case 'web':
        return TargetPlatformType.web;
      default:
        return TargetPlatformType.unknown;
    }
  }

  String get key => name;
}
