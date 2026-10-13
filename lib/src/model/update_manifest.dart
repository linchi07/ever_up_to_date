import 'channel_info.dart';

/// Top-level manifest model parsed from update configuration JSON.
class UpdateManifest {
  final int schemaVersion;
  final String? appId;
  final Map<String, ChannelInfo> channels;

  const UpdateManifest({
    this.schemaVersion = 1,
    this.appId,
    required this.channels,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['version'] as int? ?? 1;
    final appId = json['app_id'] as String?;
    final channels = <String, ChannelInfo>{};

    final rawChannels = json['channels'];
    if (rawChannels is Map) {
      rawChannels.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          channels[k.toString().toLowerCase()] = ChannelInfo.fromJson(v);
        }
      });
    }

    return UpdateManifest(
      schemaVersion: schemaVersion,
      appId: appId,
      channels: channels,
    );
  }

  /// Retrieves channel configuration by channel name (e.g. 'stable', 'beta').
  ChannelInfo? getChannel(String channelName) {
    return channels[channelName.toLowerCase()];
  }
}
