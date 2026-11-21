// lib/core/utils/app_version.dart
//
// Analyse et formatage de la version applicative.
//
// StreetPhare suit un versionnement sémantique enrichi :
//   - `0.4.0`            → version finale de production (stable)
//   - `0.4.0-alpha`      → alpha (test)
//   - `0.4.0-beta.1`     → beta (test)
//   - `0.4.0-rc.1`       → release candidate
//   - suffixe `+N`       → numéro de build (ex: `0.4.0-alpha+4`)
//
// Cette classe permet de reconnaître et d'afficher le stade d'une version.

/// Stade de publication d'une version.
enum ReleaseStage { alpha, beta, releaseCandidate, stable, unknown }

/// Déduit le stade à partir d'un suffixe pré-release (ex: `alpha`, `beta.1`).
ReleaseStage stageFromPrerelease(String? prerelease) {
  final p = (prerelease ?? '').toLowerCase();
  if (p.isEmpty) return ReleaseStage.stable;
  if (p.startsWith('alpha')) return ReleaseStage.alpha;
  if (p.startsWith('beta')) return ReleaseStage.beta;
  if (p.startsWith('rc') || p.startsWith('pre') || p.startsWith('preview')) {
    return ReleaseStage.releaseCandidate;
  }
  return ReleaseStage.unknown;
}

/// Représente une version applicative `X.Y.Z[-prerelease][+build]`.
class AppVersion implements Comparable<AppVersion> {
  AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.prerelease,
    this.build = 0,
  });

  final int major;
  final int minor;
  final int patch;

  /// Suffixe pré-release (ex: `alpha`, `beta.1`, `rc.1`), `null` si stable.
  final String? prerelease;

  /// Numéro de build (partie `+N`).
  final int build;

  /// Analyse une chaîne de version (accepte un préfixe `v`/`V`).
  static AppVersion parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }

    var build = 0;
    final plus = s.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(s.substring(plus + 1)) ?? 0;
      s = s.substring(0, plus);
    }

    String? prerelease;
    final dash = s.indexOf('-');
    if (dash >= 0) {
      prerelease = s.substring(dash + 1);
      s = s.substring(0, dash);
    }

    final parts = s.split('.');
    int part(int i) => (i < parts.length) ? (int.tryParse(parts[i]) ?? 0) : 0;

    return AppVersion(
      major: part(0),
      minor: part(1),
      patch: part(2),
      prerelease:
          (prerelease == null || prerelease.isEmpty) ? null : prerelease,
      build: build,
    );
  }

  /// Stade de publication de cette version.
  ReleaseStage get stage => stageFromPrerelease(prerelease);

  /// Libellé lisible du stade (ex: `Alpha`, `Beta`, `RC`, `Production`).
  String get stageLabel {
    switch (stage) {
      case ReleaseStage.alpha:
        return 'Alpha';
      case ReleaseStage.beta:
        return 'Beta';
      case ReleaseStage.releaseCandidate:
        return 'RC';
      case ReleaseStage.stable:
        return 'Production';
      case ReleaseStage.unknown:
        return (prerelease == null || prerelease!.isEmpty)
            ? 'Pré-release'
            : prerelease!;
    }
  }

  /// Version de base `X.Y.Z`.
  String get baseVersion => '$major.$minor.$patch';

  /// Version d'affichage sans numéro de build (ex: `v0.4.0-alpha`).
  String get displayVersion {
    final pre =
        (prerelease == null || prerelease!.isEmpty) ? '' : '-$prerelease';
    return 'v$baseVersion$pre';
  }

  /// Libellé complet avec indication du stade (ex: `v0.4.0-alpha (Alpha)`).
  String get label => '$displayVersion ($stageLabel)';

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    final rankCompare = _stageRank.compareTo(other._stageRank);
    if (rankCompare != 0) return rankCompare;
    // Même stade : compare les suffixes pré-release (ex: alpha.4 < alpha.10).
    return _comparePrerelease(other.prerelease);
  }

  int _comparePrerelease(String? other) {
    final a = prerelease ?? '';
    final b = other ?? '';
    if (a == b) return 0;
    if (a.isEmpty) return 1; // stable > pré-release
    if (b.isEmpty) return -1;
    final aParts = a.split('.');
    final bParts = b.split('.');
    final n = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < n; i++) {
      final aSeg = i < aParts.length ? aParts[i] : '';
      final bSeg = i < bParts.length ? bParts[i] : '';
      final aNum = int.tryParse(aSeg);
      final bNum = int.tryParse(bSeg);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final c = aSeg.compareTo(bSeg);
        if (c != 0) return c;
      }
    }
    return 0;
  }

  int get _stageRank {
    switch (stage) {
      case ReleaseStage.alpha:
        return 0;
      case ReleaseStage.beta:
        return 1;
      case ReleaseStage.releaseCandidate:
        return 2;
      case ReleaseStage.stable:
      case ReleaseStage.unknown:
        return 3;
    }
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  String toString() => displayVersion;
}
