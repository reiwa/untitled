import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent, PointerSignalEvent;
import 'package:provider/provider.dart';
import 'package:test_project/RoomFinderAppEditor.dart';
import 'package:test_project/RoomFinderModels.dart';
import 'package:uuid/uuid.dart';

class TolerantPageScrollPhysics extends PageScrollPhysics {
  final bool Function() canScroll;
  final double directionTolerance;

  const TolerantPageScrollPhysics({
    required this.canScroll,
    this.directionTolerance = pi / 6,
    ScrollPhysics? parent,
  }) : super(parent: parent);

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      canScroll() && super.shouldAcceptUserOffset(position);

  @override
  TolerantPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return TolerantPageScrollPhysics(
      canScroll: canScroll,
      directionTolerance: directionTolerance,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!canScroll()) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset * 0.9);
  }

  @override
  bool get allowImplicitScrolling =>
      canScroll() && super.allowImplicitScrolling;
}

class _ElevatorVerticalLink {
  const _ElevatorVerticalLink({
    required this.origin,
    required this.isUpward,
    required this.color,
    required this.targetFloor,
    this.highlight = false,
    this.message,
  });

  final Offset origin;
  final bool isUpward;
  final Color color;
  final int targetFloor;
  final bool highlight;
  final String? message;
}

enum CustomViewMode { editor, finder }

abstract class CustomView extends StatefulWidget {
  const CustomView({super.key, required this.mode});

  final CustomViewMode mode;
}

mixin InteractiveImageMixin<T extends CustomView> on State<T> {
  Offset? tapPosition;
  CachedSData? selectedElement;

  bool isDragging = false;
  bool isConnecting = false;
  CachedSData? connectingStart;
  Offset? previewPosition;

  String? activeBuildingId;

  int _currentFloor = 1;
  int get currentFloor => _currentFloor;
  late PageController pageController;

  bool isPageScrollable = true;

  bool get enableElementDrag => widget.mode == CustomViewMode.editor;

  @protected
  bool get showTapDot => widget.mode == CustomViewMode.editor;

  bool _isPointerSignalActive = false;

  CachedSData? _pendingFocusElement;
  bool _suppressClearOnPageChange = false;

  bool get canSwipeFloors {
    final scale = transformationController.value.getMaxScaleOnAxis();
    final canSwipeWhileConnectingElevator =
        isConnecting && (connectingStart?.type == PlaceType.elevator);
    return !_isPointerSignalActive &&
        !isDragging &&
        (!isConnecting || canSwipeWhileConnectingElevator) &&
        scale <= 1.05;
  }

  PlaceType currentType = PlaceType.room;
  final TransformationController transformationController =
      TransformationController();
  final double _minScale = 0.8;
  final double _maxScale = 8.0;

  @override
  void dispose() {
    transformationController.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int pageIndex) {
    final bDataContainer = context.read<BDataContainer>();
    setState(() {
      _currentFloor = bDataContainer.floorCount - pageIndex;
      activeBuildingId = bDataContainer.activeBuildingId;

      if (!_suppressClearOnPageChange) {
        tapPosition = null;
        selectedElement = null;
        if (this is EditorControllerHost) {
          (this as EditorControllerHost).nameController.clear();
          (this as EditorControllerHost).xController.clear();
          (this as EditorControllerHost).yController.clear();
        }
      }

      isDragging = false;
      //isConnecting = false;
      //connectingStart = null;
      //previewPosition = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingFocusIfAny();
    });
  }

  void onTapDetected(Offset position) {
    setState(() {
      selectedElement = null;
    });
  }

  void _updateEditorControllersPosition(Offset position) {
    if (this is! EditorControllerHost) return;
    final host = this as EditorControllerHost;
    host.xController.text = position.dx.toStringAsFixed(0);
    host.yController.text = position.dy.toStringAsFixed(0);
  }

  @protected
  void syncToBuilding(BDataContainer container, {CachedSData? focusElement}) {
    final int targetFloor = focusElement?.floor ?? 1;
    final int clampedFloor = targetFloor < 1
        ? 1
        : (targetFloor > container.floorCount
              ? container.floorCount
              : targetFloor);
    final int pageIndex = container.floorCount - clampedFloor;

    final bool needsFloorChange = clampedFloor != _currentFloor;

    setState(() {
      activeBuildingId = container.activeBuildingId;
      _currentFloor = clampedFloor;

      if (needsFloorChange && focusElement != null) {
        _pendingFocusElement = focusElement;
        _suppressClearOnPageChange = true;
        tapPosition = null;
      } else {
        tapPosition = focusElement?.position;
        selectedElement = focusElement;
        transformationController.value = Matrix4.identity();
      }

      isDragging = false;
      isConnecting = false;
      connectingStart = null;
      previewPosition = null;
    });

    if (needsFloorChange) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pageController.hasClients) {
          pageController.jumpToPage(pageIndex);
        } else {
          _applyPendingFocusIfAny();
        }
      });
    }
  }

  void _applyPendingFocusIfAny() {
    if (_pendingFocusElement != null) {
      final focus = _pendingFocusElement!;
      setState(() {
        selectedElement = focus;
        tapPosition = focus.position;
        transformationController.value = Matrix4.identity();
      });
    }
    _pendingFocusElement = null;
    _suppressClearOnPageChange = false;
  }

  ScrollPhysics _pagePhysics = const NeverScrollableScrollPhysics();

  @override
  void initState() {
    super.initState();
    final bool canSwipe = canSwipeFloors;
    //_pagePhysics = const NeverScrollableScrollPhysics();
    _pagePhysics = TolerantPageScrollPhysics(
      canScroll: () => true,
      directionTolerance: pi / 6,
    );
  }

  bool _pendingContainerSync = false;

  Widget buildInteractiveImage() {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.green.withValues(alpha: 0.45),
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        clipBehavior: Clip.hardEdge,
        child: Consumer<BDataContainer>(
          builder: (context, bDataContainer, child) {
            _ensureActiveBuildingSynced(bDataContainer);

            return Listener(
              child: PageView.builder(
                controller: pageController,
                scrollDirection: Axis.vertical,
                physics: _pagePhysics,
                itemCount: bDataContainer.floorCount,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, pageIndex) {
                  final int floor = bDataContainer.floorCount - pageIndex;

                  final double pointerSize =
                      12 /
                      sqrt(transformationController.value.getMaxScaleOnAxis());

                  return _buildFloorPage(
                    context,
                    bDataContainer,
                    floor,
                    pointerSize,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _ensureActiveBuildingSynced(BDataContainer container) {
    if (widget.mode == CustomViewMode.editor) {
      final bool changed = container.ensureDraftReadyForEditor();
      if (changed) return;
    }

    final containerActiveId = container.activeBuildingId;

    if (widget.mode == CustomViewMode.editor &&
        containerActiveId != BDataContainer.draftBuildingId) {
      if (_pendingContainerSync) return;
      _pendingContainerSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        container.startDraftFromActive();
        _pendingContainerSync = false;
      });
      return;
    }

    if (widget.mode == CustomViewMode.finder &&
        (containerActiveId == null ||
            containerActiveId == BDataContainer.draftBuildingId)) {
      final fallbackId = container.firstNonDraftBuildingId;
      if (fallbackId != null &&
          fallbackId != containerActiveId &&
          !_pendingContainerSync) {
        _pendingContainerSync = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          container.setActiveBuilding(fallbackId);
          _pendingContainerSync = false;
        });
      }
      return;
    }

    final bool buildingMismatch =
        containerActiveId != null && containerActiveId != activeBuildingId;
    final bool floorOutOfRange =
        containerActiveId != null && currentFloor > container.floorCount;

    if ((buildingMismatch || floorOutOfRange) && !_pendingContainerSync) {
      _pendingContainerSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        syncToBuilding(container);
        _pendingContainerSync = false;
      });
    }
  }

  Widget _buildFloorPage(
    BuildContext context,
    BDataContainer bDataContainer,
    int floor,
    double pointerSize,
  ) {
    final relevantElements = bDataContainer.cachedSDataList
        .where((sData) => sData.floor == floor)
        .toList();
    final passageEdges = bDataContainer.getGraphEdges(floor: floor);

    final elementsById = {
      for (final element in bDataContainer.cachedSDataList) element.id: element,
    };

    final routeSegments = bDataContainer.activeRouteSegments;
    final bool hasActiveRoute = routeSegments.isNotEmpty;
    final Set<String> routeNodeIds = {
      for (final node in bDataContainer.activeRouteNodes) node.id,
    };
    final Set<String> routeElevatorPairs = {};
    final Set<String> routeElevatorDirections = {};
    final routeVisualSegments = <RouteVisualSegment>[];

    var cachedScale = transformationController.value.getMaxScaleOnAxis();
    for (final segment in routeSegments) {
      if (segment.from.floor == floor && segment.to.floor == floor) {
        routeVisualSegments.add(
          RouteVisualSegment(
            start: segment.from.position,
            end: segment.to.position,
          ),
        );
      }
      if (segment.from.floor != segment.to.floor &&
          (segment.from.type == PlaceType.elevator ||
              segment.to.type == PlaceType.elevator)) {
        final sortedIds = [segment.from.id, segment.to.id]..sort();
        routeElevatorPairs.add('${sortedIds[0]}|${sortedIds[1]}');
        routeElevatorDirections.add('${segment.from.id}->${segment.to.id}');
      }
    }

    bool routeMatchesDirection(String fromId, String toId) =>
        routeElevatorDirections.contains('$fromId->$toId');

    bool routeUsesPair(String a, String b) {
      if (!hasActiveRoute) return true;
      final ids = [a, b]..sort();
      return routeElevatorPairs.contains('${ids[0]}|${ids[1]}');
    }

    final elevatorLinks = <_ElevatorVerticalLink>[];
    void pushElevatorLink(CachedSData source, CachedSData target) {
      if (source.floor != floor) return;
      if (!routeUsesPair(source.id, target.id)) return;
      final bool matchesDirection = routeMatchesDirection(source.id, target.id);
      if (hasActiveRoute && !matchesDirection) {
        return;
      }
      elevatorLinks.add(
        _ElevatorVerticalLink(
          origin: source.position,
          isUpward: target.floor > source.floor,
          color: PlaceType.elevator.color,
          targetFloor: target.floor,
          highlight: matchesDirection,
          message: widget.mode == CustomViewMode.editor
              ? '${target.floor}階'
              : (matchesDirection ? 'エレベーターで${target.floor}階へ' : null),
        ),
      );
    }

    for (final edgeSet in bDataContainer.cachedPDataList.expand(
      (pData) => pData.edges,
    )) {
      if (edgeSet.length != 2) continue;
      final ids = edgeSet.toList(growable: false);
      final first = elementsById[ids[0]];
      final second = elementsById[ids[1]];
      if (first == null || second == null) continue;
      if (first.type != PlaceType.elevator ||
          second.type != PlaceType.elevator) {
        continue;
      }
      if (first.floor == second.floor) continue;
      pushElevatorLink(first, second);
      pushElevatorLink(second, first);
    }

    Edge? previewEdge;
    if (isConnecting &&
        connectingStart != null &&
        previewPosition != null &&
        connectingStart!.floor == floor) {
      previewEdge = Edge(
        start: connectingStart!.position,
        end: previewPosition!,
      );
    }

    final String imagePath =
        'assets/images/${bDataContainer.imageNamePattern}_${floor}f.png';

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final viewerSize = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : (constraints.minWidth.isFinite
                    ? constraints.minWidth
                    : mediaSize.width),
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : (constraints.minHeight.isFinite
                    ? constraints.minHeight
                    : mediaSize.height),
        );
        return Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.green.withValues(alpha: 0.45),
                width: 1.0,
              ),
              bottom: BorderSide(
                color: Colors.green.withValues(alpha: 0.45),
                width: 1.0,
              ),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
                InteractiveViewer(
                  transformationController: transformationController,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  panEnabled: true,
                  clipBehavior: Clip.hardEdge,
                  boundaryMargin: const EdgeInsets.all(200),
                  onInteractionStart: (details) {
                    debugPrint('pass - Interaction started');
                    cachedScale = transformationController.value
                        .getMaxScaleOnAxis();
                  },
                  onInteractionEnd: (details) {
                    if (transformationController.value.getMaxScaleOnAxis() <=
                        1.05 && cachedScale -
                            transformationController.value
                                .getMaxScaleOnAxis() > 0) {
                          debugPrint('pass - Resetting scale + ${details.velocity.pixelsPerSecond}');
                      transformationController.value = Matrix4.identity();
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Image.asset(
                          imagePath,
                          width: 280,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text('$floor階の画像が見つかりません\n($imagePath)'),
                            );
                          },
                        ),

                        Positioned.fill(
                          child: Listener(
                            onPointerMove: (details) {
                              if (isConnecting &&
                                  connectingStart?.floor == floor) {
                                setState(() {
                                  previewPosition = details.localPosition;
                                });
                              }
                            },
                            child: GestureDetector(
                              onTapDown: (details) {
                                onTapDetected(details.localPosition);
                              },
                              child: Container(color: Colors.transparent),
                            ),
                          ),
                        ),

                        ...relevantElements.asMap().entries.map((entry) {
                          final sData = entry.value;
                          final isSelected = selectedElement?.id == sData.id;
                          final baseColor = sData.type.color;
                          final color =
                              routeNodeIds.isNotEmpty &&
                                  !routeNodeIds.contains(sData.id) &&
                                  !isSelected
                              ? baseColor.withValues(alpha: 0.5)
                              : baseColor;

                          return _NodeMarker(
                            key: ValueKey('${floor}_${sData.id}'),
                            data: isSelected && selectedElement != null
                                ? selectedElement!
                                : sData,
                            isSelected: isSelected,
                            pointerSize: pointerSize,
                            color: color,
                            enableDrag: enableElementDrag,
                            isConnecting: isConnecting,
                            onTap: () {
                              if (isConnecting) {
                                onTapDetected(sData.position);
                              } else {
                                final newSelected = isSelected ? null : sData;
                                setState(() {
                                  selectedElement = newSelected;

                                  if (newSelected != null) {
                                    tapPosition = newSelected.position;
                                    if (this is EditorControllerHost) {
                                      final host = this as EditorControllerHost;
                                      host.nameController.text =
                                          newSelected.name;
                                    }
                                    _updateEditorControllersPosition(
                                      newSelected.position,
                                    );
                                  } else {
                                    tapPosition = null;
                                    if (this is EditorControllerHost) {
                                      final host = this as EditorControllerHost;
                                      host.nameController.clear();
                                      host.xController.clear();
                                      host.yController.clear();
                                    }
                                  }
                                });
                              }
                            },
                            onDragStart: () {
                              if (!isDragging) {
                                setState(() => isDragging = true);
                              }
                            },
                            onDragUpdate: (position) {
                              if (!isSelected) return;
                            },
                            onDragEnd: (position) {
                              if (!isSelected || selectedElement == null) {
                                setState(() => isDragging = false);
                                return;
                              }
                              final updatedData = selectedElement!.copyWith(
                                position: position,
                              );
                              setState(() {
                                isDragging = false;
                                selectedElement = updatedData;
                                tapPosition = position;
                              });
                              _updateEditorControllersPosition(position);
                              context.read<BDataContainer>().updateSData(
                                updatedData,
                              );
                            },
                          );
                        }).toList(),

                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: viewerSize,
                              painter: PassagePainter(
                                edges: passageEdges,
                                previewEdge: previewEdge,
                                connectingType: connectingStart?.type,
                                scale: transformationController.value
                                    .getMaxScaleOnAxis(),
                                routeSegments: routeVisualSegments,
                                viewerSize: viewerSize,
                                elevatorLinks: elevatorLinks,
                                repaint: transformationController,
                              ),
                            ),
                          ),
                        ),

                        if (showTapDot &&
                            tapPosition != null &&
                            selectedElement == null)
                          Positioned(
                            left: tapPosition!.dx - pointerSize / 8 * 5 / 2,
                            top: tapPosition!.dy - pointerSize / 8 * 5 / 2,
                            child: GestureDetector(
                              onTap: () {
                                onTapDetected(tapPosition!);
                              },
                              onDoubleTap: () {
                                if (tapPosition == null) return;
                                final bDataContainer = context
                                    .read<BDataContainer>();
                                final newSData = CachedSData(
                                  id: const Uuid().v4(),
                                  name: '新しい要素',
                                  position: tapPosition!,
                                  floor: floor,
                                  type: currentType,
                                );
                                bDataContainer.addSData(newSData);
                                setState(() {
                                  tapPosition = null;
                                  selectedElement = null;
                                  isDragging = false;
                                });
                                if (this is EditorControllerHost) {
                                  final host = this as EditorControllerHost;
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
                          ),
                      ],
                    ),
                  ),
                ),

              /*Positioned(
                right: 10.0,
                bottom: 10.0,
                child: IconButton(
                  icon: Icon(
                    transformationController.value.getMaxScaleOnAxis() <= 1.0
                        ? Icons.zoom_out_map
                        : Icons.zoom_in_map,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.7),
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: () {
                    if (transformationController.value.getMaxScaleOnAxis() <=
                        1.0) {
                      transformationController.value = Matrix4.identity()
                        ..scale(1.1);
                    } else {
                      transformationController.value = Matrix4.identity();
                    }
                    setState(() {});
                  },
                ),
              ),*/
            ],
          ),
        );
      },
    );
  }
}

class PassagePainter extends CustomPainter {
  final List<Edge> edges;
  final Edge? previewEdge;
  final PlaceType? connectingType;
  final double scale;
  final List<RouteVisualSegment> routeSegments;
  final Size viewerSize;
  final List<_ElevatorVerticalLink> elevatorLinks;

  PassagePainter({
    required this.edges,
    this.previewEdge,
    this.connectingType,
    required this.scale,
    this.routeSegments = const [],
    required this.viewerSize,
    this.elevatorLinks = const [],
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = PlaceType.passage.color;
    final previewColor = (connectingType ?? PlaceType.passage).color;

    final edgePaint = Paint()
      ..color = baseColor.withValues(alpha: 0.8)
      ..strokeWidth = 3.0 / scale.clamp(1.0, 10.0)
      ..style = PaintingStyle.stroke;

    final bool drawBaseEdges = routeSegments.isEmpty;
    if (drawBaseEdges) {
      for (final edge in edges) {
        canvas.drawLine(edge.start, edge.end, edgePaint);
      }
    }

    if (routeSegments.isNotEmpty) {
      _paintRouteSegments(canvas);
    }

    if (previewEdge != null) {
      final previewPaint = Paint()
        ..color = previewColor.withValues(alpha: 0.5)
        ..strokeWidth = 2.0 / scale.clamp(1.0, 10.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final dashPath = _dashPath(
        previewEdge!.start,
        previewEdge!.end,
        5.0,
        5.0,
      );
      canvas.drawPath(dashPath, previewPaint);
    }
    if (elevatorLinks.isNotEmpty) {
      _paintElevatorLinks(canvas);
    }
  }

  void _paintRouteSegments(Canvas canvas) {
    final double effectiveScale = scale.clamp(1.0, 10.0);
    final Paint chevronPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3.6 / effectiveScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final segment in routeSegments) {
      _drawChevronSequence(canvas, segment, chevronPaint, effectiveScale);
    }
  }

  void _drawChevronSequence(
    Canvas canvas,
    RouteVisualSegment segment,
    Paint chevronPaint,
    double effectiveScale,
  ) {
    final Offset delta = segment.end - segment.start;
    final double length = delta.distance;
    if (length <= 0.0001) return;

    final Offset direction = delta / length;
    final Offset perpendicular = Offset(-direction.dy, direction.dx);
    final double spacing = 16.0 / effectiveScale;
    final double depth = 12.0 / effectiveScale;
    final double halfWidth = 9.0 / effectiveScale;
    final double tailPadding = max(depth * 1.0, 0.0 / effectiveScale);

    final List<double> positions = [];
    double walk = spacing * 0.6;
    while (walk < length - tailPadding) {
      positions.add(walk);
      walk += spacing;
    }

    final double finalPosition = length - tailPadding;
    if (finalPosition > depth &&
        (positions.isEmpty ||
            (finalPosition - positions.last) > (spacing * 0.4))) {
      positions.add(finalPosition);
    } else if (positions.isEmpty) {
      positions.add(length / 2);
    }

    for (final double position in positions) {
      final Offset tip = segment.start + direction * position;
      _drawChevron(
        canvas,
        tip,
        direction,
        perpendicular,
        depth,
        halfWidth,
        chevronPaint,
      );
    }
  }

  void _drawChevron(
    Canvas canvas,
    Offset tip,
    Offset direction,
    Offset perpendicular,
    double depth,
    double halfWidth,
    Paint paint,
  ) {
    final Offset base = tip - direction * depth;
    final Offset left = base + perpendicular * halfWidth;
    final Offset right = base - perpendicular * halfWidth;
    canvas.drawLine(tip, left, paint);
    canvas.drawLine(tip, right, paint);
  }

  Path _dashPath(Offset start, Offset end, double dashWidth, double dashSpace) {
    return Path()..addPath(
      _generateDashedLine(start, end, dashWidth, dashSpace),
      Offset.zero,
    );
  }

  Path _generateDashedLine(
    Offset start,
    Offset end,
    double dashWidth,
    double dashSpace,
  ) {
    final path = Path();
    final totalLength = (end - start).distance;
    final fullDash = dashWidth + dashSpace;
    final numDashes = (totalLength / fullDash).floor();

    for (int i = 0; i < numDashes; i++) {
      final dashStart = start + (end - start) * (i * fullDash / totalLength);
      final dashEnd =
          start + (end - start) * ((i * fullDash + dashWidth) / totalLength);
      path.moveTo(dashStart.dx, dashStart.dy);
      path.lineTo(dashEnd.dx, dashEnd.dy);
    }
    return path;
  }

  void _paintElevatorLinks(Canvas canvas) {
    const double baseLength = 60.0;
    final double effectiveScale = scale.clamp(1.0, 10.0);
    for (final link in elevatorLinks) {
      final double direction = link.isUpward ? -1.0 : 1.0;
      final double arrowLength = baseLength / effectiveScale;
      final Offset endPoint = link.origin + Offset(0, arrowLength * direction);
      final Color arrowColorBase = link.highlight
          ? Colors.orangeAccent
          : link.color;
      final Paint shaftPaint = Paint()
        ..color = arrowColorBase.withValues(alpha: link.highlight ? 1.0 : 0.4)
        ..strokeWidth = 3.2 / effectiveScale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(link.origin, endPoint, shaftPaint);

      final double headSize = 6.0 / effectiveScale;
      final Path headPath = Path()
        ..moveTo(endPoint.dx - headSize, endPoint.dy)
        ..lineTo(endPoint.dx + headSize, endPoint.dy)
        ..lineTo(endPoint.dx, endPoint.dy + headSize * direction * 1.5)
        ..close();

      canvas.drawPath(
        headPath,
        Paint()
          ..color = shaftPaint.color
          ..style = PaintingStyle.fill,
      );

      if (link.message != null && link.message!.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: link.message,
            style: TextStyle(
              color: link.highlight ? shaftPaint.color : Colors.black87,
              fontSize: 10.0 / effectiveScale,
              fontWeight: link.highlight ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final Offset labelOffset =
            endPoint +
            Offset(
              6.0 / effectiveScale,
              direction == -1.0 ? -textPainter.height : headSize * 0.5,
            );
        textPainter.paint(canvas, labelOffset);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PassagePainter old) {
    if (old.viewerSize != viewerSize) return true;
    if (old.routeSegments != routeSegments) return true;
    if (old.connectingType != connectingType) return true;
    if ((old.previewEdge?.start != previewEdge?.start) ||
        (old.previewEdge?.end != previewEdge?.end)) {
      return true;
    }
    if (old.edges.length != edges.length) return true;
    for (int i = 0; i < edges.length; i++) {
      if (old.edges[i].start != edges[i].start ||
          old.edges[i].end != edges[i].end) {
        return true;
      }
    }
    if (old.elevatorLinks.length != elevatorLinks.length) return true;
    for (int i = 0; i < elevatorLinks.length; i++) {
      final oldLink = old.elevatorLinks[i];
      final newLink = elevatorLinks[i];
      if (oldLink.origin != newLink.origin ||
          oldLink.isUpward != newLink.isUpward ||
          oldLink.targetFloor != newLink.targetFloor ||
          oldLink.highlight != newLink.highlight ||
          oldLink.message != newLink.message) {
        return true;
      }
    }
    if (old.routeSegments.length != routeSegments.length) return true;
    for (int i = 0; i < routeSegments.length; i++) {
      if (old.routeSegments[i].start != routeSegments[i].start ||
          old.routeSegments[i].end != routeSegments[i].end) {
        return true;
      }
    }
    return false;
  }
}

class _NodeMarker extends StatefulWidget {
  const _NodeMarker({
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
  State<_NodeMarker> createState() => _NodeMarkerState();
}

class _NodeMarkerState extends State<_NodeMarker> {
  Offset? _dragOverride;
  bool _isDragging = false;

  bool get _canDrag =>
      widget.enableDrag && widget.isSelected && !widget.isConnecting;

  double get _baseSize => widget.pointerSize;
  double get _selectedSize => widget.pointerSize / 8 * 10;

  Offset get _effectivePosition => _dragOverride ?? widget.data.position;

  double get _effectiveSize => widget.isSelected ? _selectedSize : _baseSize;

  @override
  void didUpdateWidget(covariant _NodeMarker oldWidget) {
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
