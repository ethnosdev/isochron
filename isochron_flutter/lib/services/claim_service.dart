import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Represents a soft lock claim on a track by a collaborator.
class ClaimInfo {
  final String user;
  final DateTime claimedAt;
  final String? machine;

  ClaimInfo({
    required this.user,
    required this.claimedAt,
    this.machine,
  });

  Map<String, dynamic> toJson() => {
    'user': user,
    'claimedAt': claimedAt.toIso8601String(),
    if (machine != null) 'machine': machine,
  };

  factory ClaimInfo.fromJson(Map<String, dynamic> json) {
    return ClaimInfo(
      user: json['user']?.toString() ?? 'Unknown Collaborator',
      claimedAt:
          DateTime.tryParse(json['claimedAt']?.toString() ?? '') ??
          DateTime.now(),
      machine: json['machine']?.toString(),
    );
  }

  /// Returns user initials for sidebar badges (e.g., "Alice Smith" -> "AS").
  String get initials {
    final parts = user.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Service managing lightweight track claim files (`<track>.claim.json`).
class ClaimService {
  /// Derives the claim sidecar path for a given alignment JSON path.
  /// Example: `alignments/GEN_01_timing.json` -> `alignments/GEN_01.claim.json`
  static String claimPath(String alignmentJsonPath) {
    final dir = p.dirname(alignmentJsonPath);
    final stem = p.basenameWithoutExtension(alignmentJsonPath);
    final base = stem.endsWith('_timing')
        ? stem.substring(0, stem.length - '_timing'.length)
        : stem;
    return p.join(dir, '$base.claim.json');
  }

  /// Reads the active claim on the given alignment file, or null if none exists.
  Future<ClaimInfo?> getClaim(String alignmentJsonPath) async {
    final file = File(claimPath(alignmentJsonPath));
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final Map<String, dynamic> map = jsonDecode(content);
      return ClaimInfo.fromJson(map);
    } catch (e) {
      debugPrint('[CLAIM] Failed to parse claim file: $e');
      return null;
    }
  }

  /// Synchronously reads active claim (useful in build methods for quick checks).
  ClaimInfo? getClaimSync(String alignmentJsonPath) {
    final file = File(claimPath(alignmentJsonPath));
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync();
      final Map<String, dynamic> map = jsonDecode(content);
      return ClaimInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Acquires or updates a claim on the given track.
  Future<void> acquireClaim(
    String alignmentJsonPath, {
    required String user,
    String? machine,
  }) async {
    final file = File(claimPath(alignmentJsonPath));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final claim = ClaimInfo(
      user: user,
      claimedAt: DateTime.now(),
      machine: machine ?? Platform.localHostname,
    );

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(claim.toJson()),
    );
    debugPrint('[CLAIM] Acquired claim on ${file.path} by $user');
  }

  /// Releases/deletes the claim on the given track.
  Future<void> releaseClaim(String alignmentJsonPath) async {
    final file = File(claimPath(alignmentJsonPath));
    if (await file.exists()) {
      try {
        await file.delete();
        debugPrint('[CLAIM] Released claim on ${file.path}');
      } catch (e) {
        debugPrint('[CLAIM] Failed to release claim: $e');
      }
    }
  }

  /// Checks if a claim belongs to the current user.
  bool isClaimedByMe(ClaimInfo claim, String currentUser) {
    return claim.user.trim().toLowerCase() == currentUser.trim().toLowerCase();
  }
}
