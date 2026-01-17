import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';

class FragmentList extends StatelessWidget {
  final List<Fragment> fragments;
  final Duration currentPos;
  final Function(int) onJumpTo;

  const FragmentList({
    super.key,
    required this.fragments,
    required this.currentPos,
    required this.onJumpTo,
  });

  @override
  Widget build(BuildContext context) {
    if (fragments.isEmpty) {
      return const Center(child: Text("No alignment data."));
    }

    return ListView.separated(
      itemCount: fragments.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final f = fragments[i];
        final isActive =
            currentPos.inMilliseconds >= (f.realStart * 1000) &&
            currentPos.inMilliseconds <= (f.realEnd * 1000);

        return ListTile(
          dense: true,
          selected: isActive,
          selectedTileColor: Colors.teal.withOpacity(0.1),
          leading: Text(
            "${f.index}",
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          title: Text(f.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            "${f.realStart.toStringAsFixed(2)}s - ${f.realEnd.toStringAsFixed(2)}s",
          ),
          onTap: () => onJumpTo(i),
        );
      },
    );
  }
}
