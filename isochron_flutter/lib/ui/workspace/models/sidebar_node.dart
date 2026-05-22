import 'package:isochron_flutter/ui/models/project_model.dart';

enum SidebarNodeType { collection, track, audio, text }

class SidebarNode {
  final String id;
  final SidebarNodeType type;
  final Collection? collection;
  final Track? track;
  final int depth;

  const SidebarNode({
    required this.id,
    required this.type,
    this.collection,
    this.track,
    required this.depth,
  });
}
