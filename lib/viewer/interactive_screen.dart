import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:test_project/models/room_finder_models.dart';
import 'package:test_project/room_editor/room_finder_app_editor.dart';
import 'package:test_project/viewer/node_marker.dart';
import 'package:test_project/viewer/passage_painter.dart';
import 'package:test_project/viewer/room_finder_viewer.dart';
import 'package:uuid/uuid.dart';

class InteractiveLayer extends StatelessWidget {
  const InteractiveLayer({
    super.key,
    required this.self,
    required this.floor,
    required this.imagePath,
    required this.viewerSize,
    required this.relevantElements,
    required this.routeNodeIds,
    required this.routeVisualSegments,
    required this.elevatorLinks,
    required this.passageEdges,
    this.previewEdge,
    required this.ref,
  });

  final InteractiveImageMixin self;
  final int floor;
  final String imagePath;
  final Size viewerSize;
  final List<CachedSData> relevantElements;
  final Set<String> routeNodeIds;
  final List<RouteVisualSegment> routeVisualSegments;
  final List<ElevatorVerticalLink> elevatorLinks;
  final List<Edge> passageEdges;
  final Edge? previewEdge;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    var cachedScale = self.transformationController.value.getMaxScaleOnAxis();
    return InteractiveViewer(
      transformationController: self.transformationController,
      minScale: self.minScale,
      maxScale: self.maxScale,
      panEnabled: true,
      clipBehavior: Clip.hardEdge,
      boundaryMargin: const EdgeInsets.all(200),
      onInteractionStart: (_) {
        cachedScale = self.transformationController.value.getMaxScaleOnAxis();
      },
      onInteractionEnd: (_) {
        final controller = self.transformationController;
        if (controller.value.getMaxScaleOnAxis() <= 1.05 &&
            cachedScale - controller.value.getMaxScaleOnAxis() > 0) {
          controller.value = Matrix4.identity();
        }
      },
      child: _InteractiveContent(
        self: self,
        floor: floor,
        imagePath: imagePath,
        viewerSize: viewerSize,
        relevantElements: relevantElements,
        routeNodeIds: routeNodeIds,
        routeVisualSegments: routeVisualSegments,
        elevatorLinks: elevatorLinks,
        passageEdges: passageEdges,
        previewEdge: previewEdge,
        ref: ref,
      ),
    );
  }
}

class _InteractiveContent extends StatelessWidget {
  const _InteractiveContent({
    required this.self,
    required this.floor,
    required this.imagePath,
    required this.viewerSize,
    required this.relevantElements,
    required this.routeNodeIds,
    required this.routeVisualSegments,
    required this.elevatorLinks,
    required this.passageEdges,
    this.previewEdge,
    required this.ref,
  });

  final InteractiveImageMixin self;
  final int floor;
  final String imagePath;
  final Size viewerSize;
  final List<CachedSData> relevantElements;
  final Set<String> routeNodeIds;
  final List<RouteVisualSegment> routeVisualSegments;
  final List<ElevatorVerticalLink> elevatorLinks;
  final List<Edge> passageEdges;
  final Edge? previewEdge;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Image.asset(
            imagePath,
            width: 280,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return Center(child: Text('$floor階の画像が見つかりません\n($imagePath)'));
            },
          ),
          _GestureLayer(self: self, floor: floor),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                size: viewerSize,
                painter: PassagePainter(
                  edges: passageEdges,
                  previewEdge: previewEdge,
                  connectingType: self.connectingStart?.type,
                  controller: self.transformationController,
                  routeSegments: routeVisualSegments,
                  viewerSize: viewerSize,
                  elevatorLinks: elevatorLinks,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: self.transformationController,
              builder: (context, child) {
                final scale = self.transformationController.value
                    .getMaxScaleOnAxis();
                final pointerSize = 12 / sqrt(scale);
                debugPrint('Scale: $scale, Pointer Size: $pointerSize');

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ...buildNodeMarkers(
                      self: self,
                      context: context,
                      floor: floor,
                      pointerSize: pointerSize,
                      relevantElements: relevantElements,
                      routeNodeIds: routeNodeIds,
                    ),

                    if (self.showTapDot &&
                        self.tapPosition != null &&
                        self.selectedElement == null)
                      _TapDot(
                        self: self,
                        pointerSize: pointerSize,
                        floor: floor,
                        ref: ref,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GestureLayer extends StatelessWidget {
  const _GestureLayer({required this.self, required this.floor});

  final InteractiveImageMixin self;
  final int floor;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Listener(
        onPointerMove: (details) {
          if (self.isConnecting && self.connectingStart?.floor == floor) {
            self.setState(() => self.previewPosition = details.localPosition);
          }
        },
        child: GestureDetector(
          onTapDown: (details) => self.onTapDetected(details.localPosition),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}

class _TapDot extends StatelessWidget {
  const _TapDot({
    required this.self,
    required this.pointerSize,
    required this.floor,
    required this.ref,
  });

  final InteractiveImageMixin self;
  final double pointerSize;
  final int floor;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: self.tapPosition!.dx - pointerSize / 8 * 5 / 2,
      top: self.tapPosition!.dy - pointerSize / 8 * 5 / 2,
      child: GestureDetector(
        onTap: () => self.onTapDetected(self.tapPosition!),
        onDoubleTap: () {
          if (self.tapPosition == null) return;
          final newSData = CachedSData(
            id: const Uuid().v4(),
            name: '新しい要素',
            position: self.tapPosition!,
            floor: floor,
            type: self.currentType,
          );
          ref.read(activeBuildingProvider.notifier).addSData(newSData);
          
          self.setState(() {
            self.tapPosition = null;
            self.selectedElement = null;
            self.isDragging = false;
          });
          if (self is EditorControllerHost) {
            final host = self as EditorControllerHost;
            host.nameController.clear();
            host.xController.clear();
            host.yController.clear();
          }
        },
        child: Container(
          width: pointerSize / 8 * 5,
          height: pointerSize / 8 * 5,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
