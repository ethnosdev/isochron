import 'package:path/path.dart' as p;

class _SortPart {
  final String value;
  final int? number;

  const _SortPart(this.value, this.number);
}

class _SortWrapper {
  final String originalPath;
  final List<_SortPart> parts;

  const _SortWrapper(this.originalPath, this.parts);
}

List<_SortPart> _getSortParts(String filename) {
  final regex = RegExp(r'\d+|\D+');
  return regex.allMatches(filename).map((m) {
    final val = m.group(0)!;
    return _SortPart(val, int.tryParse(val));
  }).toList();
}

int _compareWrappers(_SortWrapper a, _SortWrapper b) {
  final len = a.parts.length < b.parts.length ? a.parts.length : b.parts.length;
  for (int i = 0; i < len; i++) {
    final pA = a.parts[i];
    final pB = b.parts[i];

    if (pA.number != null && pB.number != null) {
      final cmp = pA.number!.compareTo(pB.number!);
      if (cmp != 0) return cmp;
    } else {
      final cmp = pA.value.compareTo(pB.value);
      if (cmp != 0) return cmp;
    }
  }
  return a.parts.length.compareTo(b.parts.length);
}

void naturalSort(List<String> paths) {
  final wrappers = paths.map((path) {
    final filename = p.basenameWithoutExtension(path);
    return _SortWrapper(path, _getSortParts(filename));
  }).toList();

  wrappers.sort(_compareWrappers);

  for (int i = 0; i < paths.length; i++) {
    paths[i] = wrappers[i].originalPath;
  }
}
