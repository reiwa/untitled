import 'package:flutter/material.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:test_project/viewer/room_finder_viewer.dart';

class NodeMarker extends StatefulWidget {
  const NodeMarker({
    super.key,
    required this.data,
    required this.isSelected,
    required this.pointerSize,
    required this.color,
    required this.enableDrag,
    required this.isConnecting,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final CachedSData data;
  final bool isSelected;
  final double pointerSize;
  final Color color;
  final bool enableDrag;
  final bool isConnecting;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<Offset> onDragEnd;

  @override
  State<NodeMarker> createState() => _NodeMarkerState();
}

class _NodeMarkerState extends State<NodeMarker> {
  Offset? _dragOverride;
  bool _isDragging = false;

  bool get _canDrag =>
      widget.enableDrag && widget.isSelected && !widget.isConnecting;

  double get _baseSize => widget.pointerSize;
  double get _selectedSize => widget.pointerSize / 8 * 10;

  Offset get _effectivePosition => _dragOverride ?? widget.data.position;

  double get _effectiveSize => widget.isSelected ? _selectedSize : _baseSize;

  @override
  void didUpdateWidget(covariant NodeMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSelected && oldWidget.isSelected ||
        widget.data.id != oldWidget.data.id) {
      _dragOverride = null;
      _isDragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _effectivePosition;
    final size = _effectiveSize;

    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        onScaleStart: (_) {
          if (!_canDrag) return;
          _isDragging = true;
          _dragOverride = widget.data.position;
          widget.onDragStart();
          setState(() {});
        },
        onScaleUpdate: (details) {
          if (!_canDrag || !_isDragging) return;
          if (details.scale != 1.0) return;
          final next =
              (_dragOverride ?? widget.data.position) + details.focalPointDelta;
          _dragOverride = next;
          widget.onDragUpdate(next);
          setState(() {});
        },
        onScaleEnd: (_) {
          if (!_canDrag || !_isDragging) return;
          final result = _dragOverride ?? widget.data.position;
          _isDragging = false;
          _dragOverride = null;
          widget.onDragEnd(result);
          setState(() {});
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: widget.isSelected ? Colors.orange : widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

List<Widget> buildNodeMarkers({
  required InteractiveImageMixin self,
  required BuildContext context,
  required int floor,
  required double pointerSize,
  required List<CachedSData> relevantElements,
  required Set<String> routeNodeIds,
}) {
  return relevantElements.map((sData) {
    final isSelected = self.selectedElement?.id == sData.id;
    final baseColor = sData.type.color;
    final color =
        routeNodeIds.isNotEmpty &&
            !routeNodeIds.contains(sData.id) &&
            !isSelected
        ? baseColor.withValues(alpha: 0.5)
        : baseColor;

    return NodeMarker(
      key: ValueKey('${floor}_${sData.id}'),
      data: isSelected && self.selectedElement != null
          ? self.selectedElement!
          : sData,
      isSelected: isSelected,
      pointerSize: pointerSize,
      color: color,
      enableDrag: self.enableElementDrag,
      isConnecting: self.isConnecting,
      onTap: () => self.handleMarkerTap(sData, isSelected),
      onDragStart: () {
        if (!self.isDragging) {
          self.setState(() => self.isDragging = true);
        }
      },
      onDragUpdate: (_) {},
      onDragEnd: (position) => self.handleMarkerDragEnd(position, isSelected),
    );
  }).toList();
}
