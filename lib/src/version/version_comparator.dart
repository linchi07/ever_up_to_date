/// Semantic version parser and comparator.
class VersionComparator {
  /// Compares [targetVersion] (and [targetBuild]) against [currentVersion] (and [currentBuild]).
  /// Returns `true` if target is newer than current.
  static bool isNewer({
    required String currentVersion,
    int? currentBuild,
    required String targetVersion,
    int? targetBuild,
  }) {
    final versionComparison = compareSemVer(targetVersion, currentVersion);
    if (versionComparison > 0) {
      return true;
    }
    if (versionComparison < 0) {
      return false;
    }

    // When semver strings are equal, fall back to comparing build numbers if provided
    if (targetBuild != null && currentBuild != null) {
      return targetBuild > currentBuild;
    }

    return false;
  }

  /// Compares two semantic version strings according to SemVer 2.0.0 rules.
  /// Returns 1 if v1 > v2, -1 if v1 < v2, and 0 if v1 == v2.
  static int compareSemVer(String v1, String v2) {
    final parsed1 = _ParsedVersion.parse(v1);
    final parsed2 = _ParsedVersion.parse(v2);

    final numCompare = parsed1.compareNumbers(parsed2);
    if (numCompare != 0) {
      return numCompare;
    }

    return parsed1.comparePreRelease(parsed2);
  }
}

class _ParsedVersion {
  final List<int> numbers;
  final String? preRelease;
  final String? buildMetadata;

  const _ParsedVersion({
    required this.numbers,
    this.preRelease,
    this.buildMetadata,
  });

  static _ParsedVersion parse(String versionString) {
    var raw = versionString.trim();
    String? metadata;
    String? pre;

    // Extract build metadata (+...)
    final plusIndex = raw.indexOf('+');
    if (plusIndex != -1) {
      metadata = raw.substring(plusIndex + 1);
      raw = raw.substring(0, plusIndex);
    }

    // Extract pre-release (-...)
    final dashIndex = raw.indexOf('-');
    if (dashIndex != -1) {
      pre = raw.substring(dashIndex + 1);
      raw = raw.substring(0, dashIndex);
    }

    final segments = raw.split('.');
    final numbers = <int>[];
    for (final seg in segments) {
      final parsed = int.tryParse(seg);
      if (parsed != null) {
        numbers.add(parsed);
      }
    }

    return _ParsedVersion(
      numbers: numbers,
      preRelease: pre,
      buildMetadata: metadata,
    );
  }

  int compareNumbers(_ParsedVersion other) {
    final maxLength = numbers.length > other.numbers.length
        ? numbers.length
        : other.numbers.length;

    for (var i = 0; i < maxLength; i++) {
      final num1 = i < numbers.length ? numbers[i] : 0;
      final num2 = i < other.numbers.length ? other.numbers[i] : 0;
      if (num1 != num2) {
        return num1 > num2 ? 1 : -1;
      }
    }
    return 0;
  }

  int comparePreRelease(_ParsedVersion other) {
    // According to SemVer: a normal version has higher precedence than a pre-release version
    if (preRelease == null && other.preRelease != null) {
      return 1;
    }
    if (preRelease != null && other.preRelease == null) {
      return -1;
    }
    if (preRelease == null && other.preRelease == null) {
      return 0;
    }

    // Both have pre-release tags, compare segment by segment
    final parts1 = preRelease!.split('.');
    final parts2 = other.preRelease!.split('.');
    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;

    for (var i = 0; i < maxLen; i++) {
      if (i >= parts1.length) return -1;
      if (i >= parts2.length) return 1;

      final p1 = parts1[i];
      final p2 = parts2[i];
      final n1 = int.tryParse(p1);
      final n2 = int.tryParse(p2);

      if (n1 != null && n2 != null) {
        if (n1 != n2) return n1 > n2 ? 1 : -1;
      } else if (n1 != null && n2 == null) {
        // Numeric identifiers always have lower precedence than non-numeric identifiers
        return -1;
      } else if (n1 == null && n2 != null) {
        return 1;
      } else {
        final strComp = p1.compareTo(p2);
        if (strComp != 0) return strComp > 0 ? 1 : -1;
      }
    }

    return 0;
  }
}
