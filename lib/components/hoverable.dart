import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.child});
  final Widget child;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool isHovering = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
        cursor: SystemMouseCursors.click,
        onExit: (PointerExitEvent event) {
          // Do not change state if already hovering
          if (isHovering) {
            setState(() {
              isHovering = false;
            });
          }
        },
        onEnter: (PointerEnterEvent event) {
          // Do not change state if already hovering
          if (!isHovering) {
            setState(() {
              isHovering = true;
            });
          }
        },
        child: Opacity(
          opacity: isHovering ? 0.5 : 1,
          child: widget.child,
        ));
  }
}
