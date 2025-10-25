import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent, PointerSignalEvent;
import 'package:provider/provider.dart';
import 'package:test_project/RoomFinderAppEditor.dart';

abstract class PlaceDescriptor {
  Color get color;
  bool get isGraphNode;
  String get label;
}

class _PlaceDescriptor implements PlaceDescriptor {
  const _PlaceDescriptor({
    required this.color,
    required this.isGraphNode,
    required this.label,
  });

  @override
  final Color color;
  @override
  final bool isGraphNode;
  @override
  final String label;
}

enum PlaceType implements PlaceDescriptor {
  room(_PlaceDescriptor(color: Colors.blue, isGraphNode: false, label: '部屋')),
  passage(
    _PlaceDescriptor(color: Colors.green, isGraphNode: true, label: '廊下'),
  ),
  elevator(
    _PlaceDescriptor(color: Colors.purple, isGraphNode: true, label: '階段'),
  ),
  entrance(
    _PlaceDescriptor(color: Colors.teal, isGraphNode: true, label: '入口'),
  );

  const PlaceType(this._descriptor);

  final _PlaceDescriptor _descriptor;

  @override
  Color get color => _descriptor.color;

  @override
  bool get isGraphNode => _descriptor.isGraphNode;

  @override
  String get label => _descriptor.label;
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

  CachedSData copyWith({
    String? id,
    String? name,
    Offset? position,
    int? floor,
    PlaceType? type,
  }) {
    return CachedSData(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      floor: floor ?? this.floor,
      type: type ?? this.type,
    );
  }
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

class BuildingSnapshot {
  BuildingSnapshot({
    required this.id,
    required this.name,
    required this.floorCount,
    required this.imagePattern,
    required this.elements,
    required this.passages,
  });

  String id;
  String name;
  int floorCount;
  String imagePattern;
  final List<CachedSData> elements;
  final List<CachedPData> passages;

  Iterable<CachedSData> get rooms =>
      elements.where((element) => element.type == PlaceType.room);
}

class BuildingRoomInfo {
  BuildingRoomInfo({
    required this.buildingId,
    required this.buildingName,
    required this.room,
  });

  final String buildingId;
  final String buildingName;
  final CachedSData room;
}

class BDataContainer extends ChangeNotifier {
  String buildingName = '';
  int floorCount = 1;
  String imageNamePattern = '';
  Map<int, Map<String, Offset>> _graphNodePositionCacheByFloor = {};
  Map<int, List<Edge>> _edgeCacheByFloor = {};
  List<CachedSData> _cachedSDataList = [];
  List<CachedPData> _cachedPDataList = [];

  List<CachedSData> _activeRouteNodes = [];
  List<CachedSData> get activeRouteNodes => _activeRouteNodes;

  void setActiveRouteNodes(List<CachedSData> nodes) {
    _activeRouteNodes = nodes;
    notifyListeners();
  }

  void clearActiveRouteNodes() {
    if (_activeRouteNodes.isEmpty) return;
    _activeRouteNodes = [];
    notifyListeners();
  }

  final Map<String, BuildingSnapshot> _buildingSnapshots = {};
  String? _activeBuildingId;

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
    if (_cachedPDataList.isEmpty) {
      _cachedPDataList.add(CachedPData(edges: {}));
    }
    final initialSnapshot = BuildingSnapshot(
      id: '__initial__',
      name: buildingName.isEmpty ? 'Default Building' : buildingName,
      floorCount: floorCount,
      imagePattern: imageNamePattern,
      elements: _cachedSDataList,
      passages: _cachedPDataList,
    );
    _buildingSnapshots[initialSnapshot.id] = initialSnapshot;
    _activeBuildingId = initialSnapshot.id;
  }

  String? get activeBuildingId => _activeBuildingId;

  BuildingSnapshot? getBuildingSnapshot(String buildingId) =>
      _buildingSnapshots[buildingId];

  List<BuildingRoomInfo> getAllRoomInfos() {
    final result = <BuildingRoomInfo>[];
    for (final snapshot in _buildingSnapshots.values) {
      for (final room in snapshot.rooms) {
        result.add(
          BuildingRoomInfo(
            buildingId: snapshot.id,
            buildingName: snapshot.name,
            room: room,
          ),
        );
      }
    }
    return result;
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
      final activeId = _activeBuildingId;
      if (activeId != null) {
        final snapshot = _buildingSnapshots[activeId];
        if (snapshot != null) {
          snapshot.name = buildingName;
          snapshot.floorCount = floorCount;
          snapshot.imagePattern = imageNamePattern;
        }
      }
      notifyListeners();
    }
  }

  void loadBuildingsFromJson(String rawJson) {
    final dynamic decoded = jsonDecode(rawJson);
    final Iterable<dynamic> buildingNodes;
    if (decoded is Map<String, dynamic>) {
      final dynamic list = decoded['buildings'];
      buildingNodes = list is List ? list : [decoded];
    } else if (decoded is List) {
      buildingNodes = decoded;
    } else {
      return;
    }

    BuildingSnapshot? firstSnapshot;
    bool changed = false;
    int fallbackIndex = 0;

    for (final dynamic node in buildingNodes) {
      if (node is! Map<String, dynamic>) continue;
      fallbackIndex += 1;
      final snapshot = _snapshotFromJson(node, fallbackIndex: fallbackIndex);
      _buildingSnapshots[snapshot.id] = snapshot;
      if (_activeBuildingId == snapshot.id) {
        _syncFromSnapshot(snapshot);
      }
      firstSnapshot ??= snapshot;
      changed = true;
    }

    if (_activeBuildingId == null && firstSnapshot != null) {
      _activeBuildingId = firstSnapshot.id;
      _syncFromSnapshot(firstSnapshot);
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setActiveBuilding(String buildingId, {bool notify = true}) {
    final snapshot = _buildingSnapshots[buildingId];
    if (snapshot == null) return;

    _activeBuildingId = buildingId;
    _syncFromSnapshot(snapshot);
    if (notify) {
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

  CachedSData? findElementById(String id) {
    try {
      return _cachedSDataList.firstWhere((element) => element.id == id);
    } catch (e) {
      return null;
    }
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
        _edgeCacheByFloor.clear();
      }
    }
  }

  void removeSData(CachedSData data) {
    _cachedSDataList.removeWhere((item) => item.id == data.id);

    if (data.type.isGraphNode) {
      _graphNodePositionCacheByFloor.clear();
      _edgeCacheByFloor.clear();
      final removedCount = _pruneEdgesLinkedTo(data.id);
      if (removedCount > 0) {
        print("Removed $removedCount edges related to ${data.id}");
      }
    }
    notifyListeners();
  }

  void addData(List<CachedSData> data) {
    _cachedSDataList.addAll(data);
    if (data.any((d) => d.type.isGraphNode)) {
      _graphNodePositionCacheByFloor.clear();
      _edgeCacheByFloor.clear();
    }
    notifyListeners();
  }

  void clear() {
    _cachedSDataList.clear();
    _graphNodePositionCacheByFloor.clear();
    _edgeCacheByFloor.clear();
    clearActiveRouteNodes();
    notifyListeners();
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
      (existingEdge) => existingEdge.containsAll(edgeSet),
    );

    if (!alreadyExists) {
      _cachedPDataList[0].edges.add(edgeSet);
      _edgeCacheByFloor.clear();
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
    final cached = _edgeCacheByFloor[floor];
    if (cached != null) return cached;

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
    _edgeCacheByFloor[floor] = validEdges;
    return validEdges;
  }

  int _pruneEdgesLinkedTo(String nodeId) {
    if (_cachedPDataList.isEmpty) return 0;
    final edges = _cachedPDataList[0].edges;
    final before = edges.length;
    edges.removeWhere((edgeSet) => edgeSet.contains(nodeId));
    return before - edges.length;
  }

  String buildSnapshot() {
    final buffer = StringBuffer()
      ..writeln('{')
      ..writeln(' "building_name": "$buildingName",')
      ..writeln(' "floor_count": $floorCount,')
      ..writeln(' "image_pattern": "$imageNamePattern",')
      ..writeln(' "elements": [');

    for (var i = 0; i < _cachedSDataList.length; i++) {
      final element = _cachedSDataList[i];
      buffer
        ..writeln('  {')
        ..writeln('   "id": "${element.id}",')
        ..writeln('   "name": "${element.name}",')
        ..writeln(
          '   "position": { "x": ${element.position.dx.round()}, "y": ${element.position.dy.round()} },',
        )
        ..writeln('   "floor": ${element.floor},')
        ..writeln('   "type": "${element.type.name}"')
        ..write('  }');
      if (i != _cachedSDataList.length - 1) buffer.write(',');
      buffer.writeln();
    }

    buffer
      ..writeln(' ],')
      ..writeln(' "edges": [');

    final allEdges = _cachedPDataList
        .expand((pData) => pData.edges)
        .where((edge) => edge.length == 2)
        .toList();

    for (var i = 0; i < allEdges.length; i++) {
      final ids = allEdges[i].toList();
      buffer.write('  ["${ids[0]}", "${ids[1]}"]');
      if (i != allEdges.length - 1) buffer.write(',');
      buffer.writeln();
    }

    buffer
      ..writeln(' ]')
      ..write('}');
    return buffer.toString();
  }

  BuildingSnapshot _snapshotFromJson(
    Map<String, dynamic> json, {
    required int fallbackIndex,
  }) {
    final rawName = json['building_name']?.toString() ?? '';
    final rawId = json['id']?.toString();
    final buildingId = (rawId != null && rawId.isNotEmpty)
        ? rawId
        : (rawName.isNotEmpty ? rawName : 'building_$fallbackIndex');
    final name = rawName.isEmpty ? buildingId : rawName;
    final floorCount = (json['floor_count'] as num?)?.toInt() ?? 1;
    final imagePattern = json['image_pattern']?.toString() ?? '';

    final elements = <CachedSData>[];
    final elementsNode = json['elements'];
    if (elementsNode is List) {
      for (final elementNode in elementsNode) {
        if (elementNode is! Map<String, dynamic>) continue;
        final id = elementNode['id']?.toString();
        if (id == null) continue;
        final elementName = elementNode['name']?.toString() ?? '';
        final floor = (elementNode['floor'] as num?)?.toInt() ?? 1;
        final typeName = elementNode['type']?.toString();
        final placeType = PlaceType.values.firstWhere(
          (value) => value.name == typeName,
          orElse: () => PlaceType.room,
        );
        Offset position = Offset.zero;
        final positionNode = elementNode['position'];
        if (positionNode is Map<String, dynamic>) {
          final x = (positionNode['x'] as num?)?.toDouble();
          final y = (positionNode['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            position = Offset(x, y);
          }
        }
        elements.add(
          CachedSData(
            id: id,
            name: elementName,
            position: position,
            floor: floor,
            type: placeType,
          ),
        );
      }
    }

    final edges = <Set<String>>{};
    final edgesNode = json['edges'];
    if (edgesNode is List) {
      for (final edgeNode in edgesNode) {
        if (edgeNode is List && edgeNode.length == 2) {
          final start = edgeNode[0]?.toString();
          final end = edgeNode[1]?.toString();
          if (start != null && end != null && start != end) {
            edges.add({start, end});
          }
        }
      }
    }

    final passages = <CachedPData>[CachedPData(edges: edges)];

    return BuildingSnapshot(
      id: buildingId,
      name: name,
      floorCount: floorCount,
      imagePattern: imagePattern,
      elements: elements,
      passages: passages,
    );
  }

  void _syncFromSnapshot(BuildingSnapshot snapshot) {
    buildingName = snapshot.name;
    floorCount = snapshot.floorCount;
    imageNamePattern = snapshot.imagePattern;
    _cachedSDataList = snapshot.elements;
    if (snapshot.passages.isEmpty) {
      snapshot.passages.add(CachedPData(edges: {}));
    }
    _cachedPDataList = snapshot.passages;
    _graphNodePositionCacheByFloor.clear();
    _edgeCacheByFloor.clear();
    clearActiveRouteNodes();
  }
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

    setState(() {
      activeBuildingId = container.activeBuildingId;
      _currentFloor = clampedFloor;
      tapPosition = focusElement?.position;
      selectedElement = focusElement;
      isDragging = false;
      isConnecting = false;
      connectingStart = null;
      previewPosition = null;
      transformationController.value = Matrix4.identity();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pageController.hasClients) {
        pageController.jumpToPage(pageIndex);
      }
    });
  }

  Widget buildInteractiveImage() {
    return Expanded(
      child: Consumer<BDataContainer>(
        builder: (context, bDataContainer, child) {
          final bool canSwipe = canSwipeFloors;
          final ScrollPhysics pagePhysics = canSwipe
              ? TolerantPageScrollPhysics(
                  canScroll: () => true,
                  directionTolerance: pi / 6,
                )
              : const NeverScrollableScrollPhysics();

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
              physics: pagePhysics,
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

    final routeNodes = bDataContainer.activeRouteNodes;
    final routeEdgesOnFloor = <Edge>[];

    if (routeNodes.length >= 2) {
      for (int i = 0; i < routeNodes.length - 1; i++) {
        final a = routeNodes[i];
        final b = routeNodes[i + 1];
        if (a.floor == floor && b.floor == floor) {
          routeEdgesOnFloor.add(Edge(start: a.position, end: b.position));
        }
      }
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

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black45, width: 1.0),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: canSwipeFloors,
            child: InteractiveViewer(
              transformationController: transformationController,
              minScale: _minScale,
              maxScale: _maxScale,
              panEnabled: !canSwipeFloors,
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
                      final color = sData.type.color;
                      final isSelected = selectedElement?.id == sData.id;

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
                                  host.nameController.text = newSelected.name;
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
                          size: Size.infinite,
                          painter: PassagePainter(
                            edges: passageEdges,
                            previewEdge: previewEdge,
                            connectingType: connectingStart?.type,
                            scale: transformationController.value
                                .getMaxScaleOnAxis(),
                            routeEdges: routeEdgesOnFloor,
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

          Positioned(
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
                if (transformationController.value.getMaxScaleOnAxis() <= 1.0) {
                  transformationController.value = Matrix4.identity()
                    ..scale(1.1);
                } else {
                  transformationController.value = Matrix4.identity();
                }
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PassagePainter extends CustomPainter {
  final List<Edge> edges;
  final Edge? previewEdge;
  final PlaceType? connectingType;
  final double scale;
  final List<Edge> routeEdges;

  PassagePainter({
    required this.edges,
    this.previewEdge,
    this.connectingType,
    required this.scale,
    this.routeEdges = const [],
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

    for (final edge in edges) {
      canvas.drawLine(edge.start, edge.end, edgePaint);
    }

    if (routeEdges.isNotEmpty) {
      final routePaint = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 5.0 / scale.clamp(1.0, 10.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (final edge in routeEdges) {
        canvas.drawLine(edge.start, edge.end, routePaint);
      }
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
  bool shouldRepaint(covariant PassagePainter old) {
    if (old.routeEdges != routeEdges) return true;
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
