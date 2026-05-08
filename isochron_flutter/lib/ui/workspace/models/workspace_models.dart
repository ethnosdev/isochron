import 'package:isochron_flutter/ui/models/project_model.dart';

// --- NODE ENUMS FOR SIDEBAR TREE ---
enum NodeType { collection, track, audio, text, settings }

class TreeSelection {
  final NodeType type;
  final Collection? collection;
  final Track? track;

  TreeSelection({required this.type, this.collection, this.track});
}
