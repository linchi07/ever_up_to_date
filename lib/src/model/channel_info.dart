import 'platform_target.dart';
import 'target_platform_type.dart';

/// Release information for a specific distribution channel.
class ChannelInfo {
  final String version;
  final int? buildNumber;
  final String? minOsVersion;
  final bool mandatory;
  final DateTime? pubDate;
  final Map<String, String> releaseNotes;
  final Map<TargetPlatformType, PlatformTarget> platforms;
  final double rolloutPercentage;
  final String? rolloutSeed;
  final bool withdrawn;

  const ChannelInfo({
    required this.version,
    this.buildNumber,
    this.minOsVersion,
    this.mandatory = false,
    this.pubDate,
    this.releaseNotes = const {},
    this.platforms = const {},
    this.rolloutPercentage = 100,
    this.rolloutSeed,
    this.withdrawn = false,
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String? ?? '0.0.0';
    final buildNumber =
        json['build_number'] as int? ?? json['buildNumber'] as int?;
    final minOsVersion = json['min_os_version'] as String?;
    final mandatory = json['mandatory'] as bool? ?? false;
    final pubDateStr = json['pub_date'] as String?;
    final pubDate = pubDateStr != null ? DateTime.tryParse(pubDateStr) : null;
    final rolloutPercentage =
        (json['rollout_percentage'] as num?)?.toDouble() ?? 100;
    if (!rolloutPercentage.isFinite ||
        rolloutPercentage < 0 ||
        rolloutPercentage > 100) {
      throw const FormatException(
        'rollout_percentage must be between 0 and 100',
      );
    }

    final releaseNotes = <String, String>{};
    final rawNotes = json['release_notes'];
    if (rawNotes is Map) {
      rawNotes.forEach((k, v) {
        releaseNotes[k.toString()] = v.toString();
      });
    } else if (rawNotes is String) {
      releaseNotes['default'] = rawNotes;
    }

    final platforms = <TargetPlatformType, PlatformTarget>{};
    final rawPlatforms = json['platforms'];
    if (rawPlatforms is Map) {
      rawPlatforms.forEach((key, val) {
        if (val is Map<String, dynamic>) {
          final platformType = TargetPlatformType.fromString(key.toString());
          platforms[platformType] = PlatformTarget.fromJson(val);
        }
      });
    }

    return ChannelInfo(
      version: version,
      buildNumber: buildNumber,
      minOsVersion: minOsVersion,
      mandatory: mandatory,
      pubDate: pubDate,
      releaseNotes: releaseNotes,
      platforms: platforms,
      rolloutPercentage: rolloutPercentage,
      rolloutSeed: json['rollout_seed'] as String?,
      withdrawn: json['withdrawn'] as bool? ?? false,
    );
  }

  /// Resolves the release notes text based on the preferred locale.
  String getLocalizedReleaseNotes([String? locale]) {
    if (releaseNotes.isEmpty) {
      return '';
    }
    if (locale != null && releaseNotes.containsKey(locale)) {
      return releaseNotes[locale]!;
    }
    if (locale != null) {
      final targetBase = locale.split(RegExp(r'[-_]')).first.toLowerCase();
      for (final entry in releaseNotes.entries) {
        final keyBase = entry.key.split(RegExp(r'[-_]')).first.toLowerCase();
        if (keyBase == targetBase) {
          return entry.value;
        }
      }
    }
    return releaseNotes['default'] ?? releaseNotes.values.first;
  }

  /// Gets the platform target definition for [platformType].
  PlatformTarget? getTarget(
    TargetPlatformType platformType, [
    String? architecture,
  ]) {
    final target = platforms[platformType];
    final variants = target?.extra['architectures'];
    if (variants is Map) {
      final variant = variants[architecture];
      return variant is Map<String, dynamic>
          ? PlatformTarget.fromJson(variant)
          : null;
    }
    return target;
  }
}
