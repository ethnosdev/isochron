import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/claim_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String alignmentPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('claim_service_test_');
    alignmentPath = p.join(tempDir.path, 'alignments', 'GEN_01_timing.json');
    Directory(p.dirname(alignmentPath)).createSync(recursive: true);
    File(alignmentPath).writeAsStringSync('[]');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ClaimService.claimPath', () {
    test('derives correct claim path by stripping _timing suffix', () {
      final path = ClaimService.claimPath('/project/alignments/GEN_01_timing.json');
      expect(path, '/project/alignments/GEN_01.claim.json');
    });

    test('derives correct claim path when filename does not have _timing suffix', () {
      final path = ClaimService.claimPath('/project/alignments/Chapter1.json');
      expect(path, '/project/alignments/Chapter1.claim.json');
    });
  });

  group('ClaimInfo model', () {
    test('computes initials correctly', () {
      expect(ClaimInfo(user: 'Alice Smith', claimedAt: DateTime.now()).initials, 'AS');
      expect(ClaimInfo(user: 'Bob', claimedAt: DateTime.now()).initials, 'BO');
      expect(ClaimInfo(user: 'John Michael Doe', claimedAt: DateTime.now()).initials, 'JD');
      expect(ClaimInfo(user: '   ', claimedAt: DateTime.now()).initials, '?');
    });

    test('roundtrips JSON cleanly', () {
      final now = DateTime.now();
      final claim = ClaimInfo(user: 'Alice Smith', claimedAt: now, machine: 'MacBook');
      final jsonMap = claim.toJson();

      final parsed = ClaimInfo.fromJson(jsonMap);
      expect(parsed.user, 'Alice Smith');
      expect(parsed.machine, 'MacBook');
      expect(parsed.claimedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });
  });

  group('ClaimService file operations', () {
    test('acquireClaim writes valid claim file and getClaim reads it', () async {
      final service = ClaimService();

      expect(await service.getClaim(alignmentPath), isNull);
      expect(service.getClaimSync(alignmentPath), isNull);

      await service.acquireClaim(
        alignmentPath,
        user: 'Alice Smith',
        machine: 'Alice-Air',
      );

      final claimFile = File(ClaimService.claimPath(alignmentPath));
      expect(claimFile.existsSync(), isTrue);

      final claim = await service.getClaim(alignmentPath);
      expect(claim, isNotNull);
      expect(claim!.user, 'Alice Smith');
      expect(claim.machine, 'Alice-Air');

      final syncClaim = service.getClaimSync(alignmentPath);
      expect(syncClaim, isNotNull);
      expect(syncClaim!.user, 'Alice Smith');
    });

    test('releaseClaim deletes the claim file', () async {
      final service = ClaimService();
      await service.acquireClaim(alignmentPath, user: 'Bob');

      expect(File(ClaimService.claimPath(alignmentPath)).existsSync(), isTrue);

      await service.releaseClaim(alignmentPath);

      expect(File(ClaimService.claimPath(alignmentPath)).existsSync(), isFalse);
      expect(await service.getClaim(alignmentPath), isNull);
    });

    test('getClaim handles corrupt JSON without throwing', () async {
      final service = ClaimService();
      final claimFile = File(ClaimService.claimPath(alignmentPath));
      claimFile.writeAsStringSync('NOT VALID JSON');

      expect(await service.getClaim(alignmentPath), isNull);
      expect(service.getClaimSync(alignmentPath), isNull);
    });

    test('isClaimedByMe correctly matches case-insensitively and trimmed', () {
      final service = ClaimService();
      final claim = ClaimInfo(user: 'Alice Smith', claimedAt: DateTime.now());

      expect(service.isClaimedByMe(claim, 'Alice Smith'), isTrue);
      expect(service.isClaimedByMe(claim, 'alice smith'), isTrue);
      expect(service.isClaimedByMe(claim, '  ALICE SMITH  '), isTrue);
      expect(service.isClaimedByMe(claim, 'Bob Jones'), isFalse);
    });
  });
}
