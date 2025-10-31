import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:test_project/models/room_finder_models.dart';
import 'package:test_project/room_editor/room_finder_app_editor.dart';
import 'package:test_project/utility/platform_utils.dart';
import 'package:test_project/viewer/interactive_image_state.dart';
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
    return Container(
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: self.canSwipeFloors,
            child: InteractiveViewer(
              transformationController: self.transformationController,
              minScale: self.minScale,
              maxScale: self.maxScale,
              panEnabled: true,
              clipBehavior: Clip.hardEdge,
              boundaryMargin: const EdgeInsets.all(200),
              onInteractionStart: (_) {
                cachedScale = self.transformationController.value
                    .getMaxScaleOnAxis();
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
            ),
          ),

          if (isDesktopOrElse)
            Positioned(
              right: 10.0,
              bottom: 10.0,
              child: IconButton(
                icon: Icon(
                  self.transformationController.value.getMaxScaleOnAxis() <= 1.0
                      ? Icons.zoom_out_map
                      : Icons.zoom_in_map,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.7),
                  foregroundColor: Colors.black87,
                ),
                onPressed: () {
                  if (self.transformationController.value.getMaxScaleOnAxis() <=
                      1.0) {
                    self.transformationController.value = Matrix4.identity()
                      ..scale(1.1);
                  } else {
                    self.transformationController.value = Matrix4.identity();
                  }
                  self.setState(() {});
                },
              ),
            ),
        ],
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
    final imageState = ref.watch(interactiveImageProvider);
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
          _GestureLayer(self: self, floor: floor, ref: ref),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                size: viewerSize,
                painter: PassagePainter(
                  edges: passageEdges,
                  previewEdge: previewEdge,
                  connectingType: imageState.connectingStart?.type,
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
                      ref: ref,
                    ),

                    if (self.showTapDot &&
                        imageState.tapPosition != null &&
                        imageState.selectedElement == null)
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
  const _GestureLayer({required this.self, required this.floor, required this.ref});

  final InteractiveImageMixin self;
  final int floor;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final imageState = ref.watch(interactiveImageProvider);
    final notifier = ref.read(interactiveImageProvider.notifier);
    return Positioned.fill(
      child: Listener(
        onPointerMove: (details) {
          if (imageState.isConnecting && imageState.connectingStart?.floor == floor) {
            notifier.updatePreviewPosition(details.localPosition);
          }
        },
        child: GestureDetector(
          onTapDown: (details) => notifier.onTapDetected(details.localPosition),
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
    final imageState = ref.watch(interactiveImageProvider);
    final notifier = ref.read(interactiveImageProvider.notifier);
    return Positioned(
      left: imageState.tapPosition!.dx - pointerSize / 8 * 5 / 2,
      top: imageState.tapPosition!.dy - pointerSize / 8 * 5 / 2,
      child: GestureDetector(
        onTap: () => notifier.onTapDetected(imageState.tapPosition!),
        onDoubleTap: () {
          if (imageState.tapPosition == null) return;
          final newSData = CachedSData(
            id: const Uuid().v4(),
            name: '新しい要素',
            position: imageState.tapPosition!,
            floor: floor,
            type: self.currentType,
          );
          ref.read(activeBuildingProvider.notifier).addSData(newSData);

          notifier.clearSelectionState();
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
