import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent, PointerSignalEvent;
import 'package:provider/provider.dart';
import 'package:test_project/RoomFinderAppEditor.dart';

enum PlaceType { room, passage, elevator, entrance }

extension PlaceTypeExtension on PlaceType {
  bool get isGraphNode {
    switch (this) {
      case PlaceType.passage:
      case PlaceType.elevator:
      case PlaceType.entrance:
        return true;
      case PlaceType.room:
      default:
        return false;
    }
  }
}

class CachedSData {
  String id;
  String name;
  Offset position;
  int floor;
  PlaceType type;

  CachedSData({
    required this.id,
    required this.name,
    required this.position,
    required this.floor,
    required this.type,
  });
}

class CachedPData {
  Set<Set<String>> edges;
  CachedPData({required this.edges});
}

class Edge {
  final Offset start;
  final Offset end;
  Edge({required this.start, required this.end});
}

class ConditionalPageScrollPhysics extends PageScrollPhysics {
  final bool Function() canScroll;

  const ConditionalPageScrollPhysics({
    required this.canScroll,
    ScrollPhysics? parent,
  }) : super(parent: parent);

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      canScroll() && super.shouldAcceptUserOffset(position);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!canScroll()) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  bool get allowImplicitScrolling =>
      canScroll() && super.allowImplicitScrolling;

  @override
  ConditionalPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ConditionalPageScrollPhysics(
      canScroll: canScroll,
      parent: super.applyTo(ancestor),
    );
  }
}

class BDataContainer extends ChangeNotifier {
  String buildingName = '';
  int floorCount = 1;
  String imageNamePattern = '';
  Map<int, Map<String, Offset>> _graphNodePositionCacheByFloor = {};
  List<CachedSData> _cachedSDataList = [];
  List<CachedPData> _cachedPDataList = [];

  BDataContainer(
    String initialBuildingName,
    int initialFloorCount,
    String initialImageNamePattern,
    List<CachedSData> initialSData,
    List<CachedPData> initialPData,
  ) {
    buildingName = initialBuildingName;
    floorCount = initialFloorCount;
    imageNamePattern = initialImageNamePattern;
    _cachedSDataList.addAll(initialSData);
    _cachedPDataList.addAll(initialPData);
  }

  List<CachedSData> get cachedSDataList => List.unmodifiable(_cachedSDataList);
  List<CachedPData> get cachedPDataList => List.unmodifiable(_cachedPDataList);

  void updateBuildingSettings({String? name, int? floors, String? pattern}) {
    bool changed = false;

    if (name != null && buildingName != name) {
      buildingName = name;
      changed = true;
    }
    if (floors != null && floorCount != floors) {
      floorCount = floors;
      changed = true;
    }
    if (pattern != null && imageNamePattern != pattern) {
      imageNamePattern = pattern;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  Map<String, Offset> getGraphNodePositionsForFloor(int floor) {
    if (!_graphNodePositionCacheByFloor.containsKey(floor)) {
      _graphNodePositionCacheByFloor[floor] = _buildGraphNodeCacheForFloor(
        floor,
      );
    }
    return _graphNodePositionCacheByFloor[floor]!;
  }

  Map<String, Offset> _buildGraphNodeCacheForFloor(int floor) {
    return {
      for (var sData in _cachedSDataList.where(
        (data) => data.type.isGraphNode && data.floor == floor,
      ))
        sData.id: sData.position,
    };
  }

  void addSData(CachedSData data) {
    _cachedSDataList.add(data);
    notifyListeners();
    if (data.type.isGraphNode) _graphNodePositionCacheByFloor.clear();
  }

  void addPData(CachedPData data) {
    _cachedPDataList.add(data);
    notifyListeners();
  }

  void updateSData(CachedSData updatedData) {
    int index = _cachedSDataList.indexWhere(
      (item) => item.id == updatedData.id,
    );

    if (index != -1) {
      _cachedSDataList[index] = updatedData;
      notifyListeners();

      if (updatedData.type.isGraphNode) {
        _graphNodePositionCacheByFloor.clear();
      }
    }
  }

  void removeSData(CachedSData data) {
    _cachedSDataList.removeWhere((item) => item.id == data.id);

    if (data.type.isGraphNode) {
      _graphNodePositionCacheByFloor.clear();

      if (_cachedPDataList.isNotEmpty) {
        final int edgesRemoved = _cachedPDataList[0].edges.length;
        _cachedPDataList[0].edges.removeWhere(
          (edgeSet) => edgeSet.contains(data.id),
        );
        print(
          "Removed ${edgesRemoved - _cachedPDataList[0].edges.length} edges related to ${data.id}",
        );
      }
    }

    notifyListeners();
  }

  void addData(List<CachedSData> data) {
    _cachedSDataList.addAll(data);
    notifyListeners();
    if (data.any((d) => d.type.isGraphNode))
      _graphNodePositionCacheByFloor.clear();
  }

  void clear() {
    _cachedSDataList.clear();
    notifyListeners();
    _graphNodePositionCacheByFloor.clear();
  }

  void addEdge(String startId, String endId) {
    if (startId == endId) {
      print("Cannot add edge to itself. Skipping.");
      return;
    }
    final edgeSet = {startId, endId};

    if (_cachedPDataList.isEmpty) {
      _cachedPDataList.add(CachedPData(edges: {}));
    }

    final alreadyExists = _cachedPDataList[0].edges.any(
      (existingEdge) =>
          existingEdge.contains(startId) && existingEdge.contains(endId),
    );

    if (!alreadyExists) {
      _cachedPDataList[0].edges.add(edgeSet);
      notifyListeners();
      print("Edge added: $edgeSet");
    } else {
      print("Edge already exists. Skipping.");
    }
  }

  bool hasEdges(String passageId) {
    if (_cachedPDataList.isEmpty) {
      return false;
    }
    return _cachedPDataList[0].edges.any(
      (edgeSet) => edgeSet.contains(passageId),
    );
  }

  List<Edge> getGraphEdges({int floor = 1}) {
    final positions = getGraphNodePositionsForFloor(floor);
    final validEdges = <Edge>[];
    for (final edgeSet in _cachedPDataList.expand((pData) => pData.edges)) {
      if (edgeSet.length != 2) continue;
      final ids = edgeSet.toList();
      final startId = ids[0], endId = ids[1];
      if (positions.containsKey(startId) && positions.containsKey(endId)) {
        validEdges.add(
          Edge(start: positions[startId]!, end: positions[endId]!),
        );
      }
    }
    return validEdges;
  }
}

abstract class CustomView extends StatefulWidget {
  const CustomView({super.key});
}

mixin InteractiveImageMixin<T extends StatefulWidget> on State<T> {
  Offset? tapPosition;
  CachedSData? selectedElement;

  bool isDragging = false;
  bool isConnecting = false;
  CachedSData? connectingStart;
  Offset? previewPosition;

  int _currentFloor = 1;
  int get currentFloor => _currentFloor;
  late PageController pageController;

  bool get showTapDot => false;

  bool _isPointerSignalActive = false;

  bool get _canSwipeFloors {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final canSwipeWhileConnectingElevator =
        isConnecting && (connectingStart?.type == PlaceType.elevator);
    return !_isPointerSignalActive &&
        !isDragging &&
        (!isConnecting || canSwipeWhileConnectingElevator) &&
        scale <= 1.05;
  }

  PlaceType currentType = PlaceType.room;
  final TransformationController _transformationController =
      TransformationController();
  final double _minScale = 0.8;
  final double _maxScale = 8.0;

  Map<PlaceType, Color> get typeColors => {
    PlaceType.room: Colors.blue,
    PlaceType.passage: Colors.green,
    PlaceType.elevator: Colors.purple,
    PlaceType.entrance: Colors.teal,
  };

  @override
  void dispose() {
    _transformationController.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int pageIndex) {
    final bDataContainer = context.read<BDataContainer>();
    setState(() {
      _currentFloor = bDataContainer.floorCount - pageIndex;

      tapPosition = null;
      selectedElement = null;
      isDragging = false;
      //isConnecting = false;
      //connectingStart = null;
      //previewPosition = null;

      if (this is EditorControllerHost) {
        (this as EditorControllerHost).nameController.clear();
        (this as EditorControllerHost).xController.clear();
        (this as EditorControllerHost).yController.clear();
      }
    });
  }

  void onTapDetected(Offset position) {
    setState(() {
      selectedElement = null;
    });
  }

  Widget buildInteractiveImage() {
    return Expanded(
      child: Consumer<BDataContainer>(
        builder: (context, bDataContainer, child) {
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.mouse,
              },
            ),
            child: PageView.builder(
              controller: pageController,
              scrollDirection: Axis.vertical,
              physics: ConditionalPageScrollPhysics(canScroll: () => _canSwipeFloors),
              itemCount: bDataContainer.floorCount,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, pageIndex) {
                final int floor = bDataContainer.floorCount - pageIndex;

                final double pointerSize =
                    12 /
                    sqrt(_transformationController.value.getMaxScaleOnAxis());

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
    );
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

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black45, width: 1.0),
      ),
      clipBehavior: Clip.hardEdge,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: _minScale,
        maxScale: _maxScale,
        panEnabled: !_canSwipeFloors,
        onInteractionUpdate: (details) => setState(() {}),
        child: Container(
          alignment: Alignment.center,
          child: Stack(
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
                    if (isConnecting && connectingStart?.floor == floor) {
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
                final index = entry.key;
                final sData = entry.value;
                final color = typeColors[sData.type] ?? Colors.grey;
                final isSelected = selectedElement == sData;

                return Positioned(
                  left:
                      sData.position.dx -
                      (isSelected ? pointerSize / 8 * 10 / 2 : pointerSize / 2),
                  top:
                      sData.position.dy -
                      (isSelected ? pointerSize / 8 * 10 / 2 : pointerSize / 2),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (isConnecting) {
                        onTapDetected(sData.position);
                      } else {
                        final newSelected = isSelected ? null : sData;
                        setState(() {
                          selectedElement = newSelected;

                          if (newSelected != null) {
                            tapPosition = newSelected.position;
                            (this as EditorControllerHost).nameController.text =
                                newSelected.name;
                            (this as EditorControllerHost).xController.text =
                                newSelected.position.dx.toStringAsFixed(0);
                            (this as EditorControllerHost).yController.text =
                                newSelected.position.dy.toStringAsFixed(0);
                          } else {
                            tapPosition = null;
                            (this as EditorControllerHost).nameController
                                .clear();
                            (this as EditorControllerHost).xController.clear();
                            (this as EditorControllerHost).yController.clear();
                          }
                        });
                      }
                    },
                    onScaleStart: (details) {
                      if (isSelected && !isConnecting) {
                        isDragging = true;
                      }
                    },
                    onScaleUpdate: (details) {
                      if (isSelected && isDragging && !isConnecting) {
                        if (details.scale != 1.0) return;

                        final Offset sceneDelta = details.focalPointDelta;
                        final Offset newPosition =
                            selectedElement!.position + sceneDelta;

                        (this as EditorControllerHost).xController.text =
                            newPosition.dx.toStringAsFixed(0);
                        (this as EditorControllerHost).yController.text =
                            newPosition.dy.toStringAsFixed(0);

                        final bDataContainer = context.read<BDataContainer>();
                        final updatedData = CachedSData(
                          id: selectedElement!.id,
                          name: (this as EditorControllerHost)
                              .nameController
                              .text,
                          position: newPosition,
                          floor: selectedElement!.floor,
                          type: selectedElement!.type,
                        );
                        bDataContainer.updateSData(updatedData);

                        setState(() {
                          selectedElement = updatedData;
                          tapPosition = newPosition;
                        });
                      }
                    },
                    onScaleEnd: (details) {
                      if (isSelected && isDragging) {
                        isDragging = false;
                      }
                    },
                    child: Container(
                      width: isSelected ? pointerSize / 8 * 10 : pointerSize,
                      height: isSelected ? pointerSize / 8 * 10 : pointerSize,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.orange : color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }).toList(),

              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: PassagePainter(
                      edges: passageEdges,
                      previewEdge: previewEdge,
                      controller: _transformationController,
                      typeColors: typeColors,
                      connectingType: connectingStart?.type,
                    ),
                  ),
                ),
              ),

              if (showTapDot && tapPosition != null && selectedElement == null)
                Positioned(
                  left: tapPosition!.dx - pointerSize / 8 * 5 / 2,
                  top: tapPosition!.dy - pointerSize / 8 * 5 / 2,
                  child: Container(
                    width: pointerSize / 8 * 5,
                    height: pointerSize / 8 * 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && mounted) {
      if (!_isPointerSignalActive) {
        setState(() {
          _isPointerSignalActive = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isPointerSignalActive = false);
          }
        });
      }
    }
  }
}

class PassagePainter extends CustomPainter {
  final List<Edge> edges;
  final Edge? previewEdge;
  final TransformationController controller;
  final Map<PlaceType, Color> typeColors;
  final PlaceType? connectingType;

  PassagePainter({
    required this.edges,
    this.previewEdge,
    required this.controller,
    required this.typeColors,
    this.connectingType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = controller.value.getMaxScaleOnAxis();

    final previewColor =
        (connectingType != null
            ? typeColors[connectingType]
            : typeColors[PlaceType.passage]) ??
        Colors.green;

    final edgePaint = Paint()
      ..color = typeColors[PlaceType.passage]!.withValues(alpha: 0.8)
      ..strokeWidth = 3.0 / scale.clamp(1.0, 10.0)
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      canvas.drawLine(edge.start, edge.end, edgePaint);
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
