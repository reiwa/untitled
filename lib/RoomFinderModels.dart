import 'dart:convert';
import 'package:flutter/material.dart';

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
  room(_PlaceDescriptor(color: Colors.blue, isGraphNode: true, label: '部屋')),
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

class RouteSegment {
  RouteSegment({required this.from, required this.to});

  final CachedSData from;
  final CachedSData to;

  bool get isSameFloor => from.floor == to.floor;

  bool matches(String startId, String endId) =>
      from.id == startId && to.id == endId;
}

class RouteVisualSegment {
  RouteVisualSegment({required this.start, required this.end});

  final Offset start;
  final Offset end;
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
  static const String draftBuildingId = '__editor_draft__';
  String buildingName = '';
  int floorCount = 1;
  String imageNamePattern = '';
  Map<int, Map<String, Offset>> _graphNodePositionCacheByFloor = {};
  Map<int, List<Edge>> _edgeCacheByFloor = {};
  List<CachedSData> _cachedSDataList = [];
  List<CachedPData> _cachedPDataList = [];

  List<CachedSData> _activeRouteNodes = [];
  List<RouteSegment> _activeRouteSegments = [];
  List<CachedSData> get activeRouteNodes =>
      List.unmodifiable(_activeRouteNodes);
  List<RouteSegment> get activeRouteSegments =>
      List.unmodifiable(_activeRouteSegments);

  void setActiveRouteNodes(List<CachedSData> nodes) {
    _activeRouteNodes = List<CachedSData>.from(nodes);
    _activeRouteSegments = [
      for (int i = 0; i < nodes.length - 1; i++)
        RouteSegment(from: nodes[i], to: nodes[i + 1]),
    ];
    notifyListeners();
  }

  void clearActiveRouteNodes() {
    if (_activeRouteNodes.isEmpty && _activeRouteSegments.isEmpty) return;
    _activeRouteNodes = [];
    _activeRouteSegments = [];
    notifyListeners();
  }

  final Map<String, BuildingSnapshot> _buildingSnapshots = {};
  String? _activeBuildingId;
  String? _pendingEditorInheritId;

  bool get hasDraftSnapshot => _buildingSnapshots.containsKey(draftBuildingId);

  String? get firstNonDraftBuildingId {
    for (final entry in _buildingSnapshots.entries) {
      if (entry.key == draftBuildingId) continue;
      return entry.key;
    }
    return null;
  }

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

  void startNewBuildingDraft() {
    _pendingEditorInheritId = null;
    final snapshot = BuildingSnapshot(
      id: draftBuildingId,
      name: '新しい建物',
      floorCount: 1,
      imagePattern: '',
      elements: <CachedSData>[],
      passages: [CachedPData(edges: {})],
    );
    _buildingSnapshots[draftBuildingId] = snapshot;
    _activeBuildingId = draftBuildingId;
    _syncFromSnapshot(snapshot);
    notifyListeners();
  }

  void startDraftFromActive() {
    _pendingEditorInheritId = null;
    final sourceId = _activeBuildingId;
    final source = (sourceId != null) ? _buildingSnapshots[sourceId] : null;

    if (source == null || source.id == draftBuildingId) {
      startNewBuildingDraft();
      return;
    }

    final elementsCopy = source.elements
        .map(
          (e) => CachedSData(
            id: e.id,
            name: e.name,
            position: e.position,
            floor: e.floor,
            type: e.type,
          ),
        )
        .toList();

    final passagesCopy = source.passages
        .map(
          (p) => CachedPData(
            edges: p.edges.map((s) => Set<String>.from(s)).toSet(),
          ),
        )
        .toList();

    final snapshot = BuildingSnapshot(
      id: draftBuildingId,
      name: source.name,
      floorCount: source.floorCount,
      imagePattern: source.imagePattern,
      elements: elementsCopy,
      passages: passagesCopy.isEmpty ? [CachedPData(edges: {})] : passagesCopy,
    );

    _buildingSnapshots[draftBuildingId] = snapshot;
    _activeBuildingId = draftBuildingId;
    _syncFromSnapshot(snapshot);
    notifyListeners();
  }

  void requestEditorInheritance(String buildingId) {
    if (buildingId == draftBuildingId) return;
    _pendingEditorInheritId = buildingId;
  }

  bool ensureDraftReadyForEditor() {
    var pendingId = _pendingEditorInheritId;
    if (pendingId != null && !_buildingSnapshots.containsKey(pendingId)) {
      pendingId = null;
      _pendingEditorInheritId = null;
    }
    if (pendingId != null) {
      _pendingEditorInheritId = null;
      if (_activeBuildingId != pendingId) {
        setActiveBuilding(pendingId, notify: false);
      }
      startDraftFromActive();
      return true;
    }
    if (_activeBuildingId == draftBuildingId) {
      if (!hasDraftSnapshot) {
        startNewBuildingDraft();
        return true;
      }
      return false;
    }
    if (_activeBuildingId == null) {
      if (hasDraftSnapshot) {
        setActiveBuilding(draftBuildingId);
      } else {
        startNewBuildingDraft();
      }
      return true;
    }
    if (hasDraftSnapshot) {
      setActiveBuilding(draftBuildingId);
      return true;
    }
    startNewBuildingDraft();
    return true;
  }

  List<BuildingRoomInfo> getAllRoomInfos() {
    final result = <BuildingRoomInfo>[];
    for (final snapshot in _buildingSnapshots.values) {
      if (snapshot.id == draftBuildingId) continue;
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
      final dynamic listNode = decoded['buildings'];
      if (listNode == null) {
        buildingNodes = [decoded];
      } else if (listNode is List) {
        buildingNodes = listNode;
      } else {
        buildingNodes = [listNode];
      }
    } else if (decoded is List) {
      buildingNodes = decoded;
    } else {
      return;
    }

    _buildingSnapshots.clear();
    BuildingSnapshot? firstSnapshot;
    bool changed = false;
    int fallbackIndex = 0;

    for (final dynamic node in buildingNodes) {
      if (node is! Map<String, dynamic>) continue;
      fallbackIndex += 1;
      final snapshot = _snapshotFromJson(node, fallbackIndex: fallbackIndex);
      _buildingSnapshots[snapshot.id] = snapshot;
      firstSnapshot ??= snapshot;
      changed = true;
    }

    if (firstSnapshot != null) {
      _activeBuildingId = firstSnapshot.id;
      _syncFromSnapshot(firstSnapshot);
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
    _pendingEditorInheritId = null;
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
      ..writeln('            "building_name": "$buildingName",')
      ..writeln('            "floor_count": $floorCount,')
      ..writeln('            "image_pattern": "$imageNamePattern",')
      ..writeln('            "elements": [');

    for (var i = 0; i < _cachedSDataList.length; i++) {
      final element = _cachedSDataList[i];
      buffer
        ..writeln('                {')
        ..writeln('                    "id": "${element.id}",')
        ..writeln('                    "name": "${element.name}",')
        ..writeln(
          '                    "position": { "x": ${element.position.dx.round()}, "y": ${element.position.dy.round()} },',
        )
        ..writeln('                    "floor": ${element.floor},')
        ..writeln('                    "type": "${element.type.name}"')
        ..write('                }');
      if (i != _cachedSDataList.length - 1) buffer.write(',');
      buffer.writeln();
    }

    buffer
      ..writeln('            ],')
      ..writeln('            "edges": [');

    final allEdges = _cachedPDataList
        .expand((pData) => pData.edges)
        .where((edge) => edge.length == 2)
        .toList();

    for (var i = 0; i < allEdges.length; i++) {
      final ids = allEdges[i].toList();
      buffer.write('                ["${ids[0]}", "${ids[1]}"]');
      if (i != allEdges.length - 1) buffer.write(',');
      buffer.writeln();
    }

    buffer
      ..writeln('            ]')
      ..write('        }');
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

  void rebuildRoomPassageEdges() {
    if (_cachedPDataList.isEmpty) {
      _cachedPDataList.add(CachedPData(edges: {}));
    }

    final elementsById = {
      for (final element in _cachedSDataList) element.id: element,
    };

    bool changed = false;
    for (final passages in _cachedPDataList) {
      passages.edges.removeWhere((edge) {
        if (edge.length != 2) return false;
        final hasRoom = edge.any(
          (id) => elementsById[id]?.type == PlaceType.room,
        );
        if (hasRoom) changed = true;
        return hasRoom;
      });
    }

    final edgeBucket = _cachedPDataList.first.edges;
    final existingEdgeKeys = <String>{};
    for (final edge in edgeBucket) {
      if (edge.length != 2) continue;
      final ids = edge.toList()..sort();
      existingEdgeKeys.add('${ids[0]}|${ids[1]}');
    }

    final roomsByFloor = <int, List<CachedSData>>{};
    final passagesByFloor = <int, List<CachedSData>>{};
    for (final element in _cachedSDataList) {
      if (element.type == PlaceType.room) {
        roomsByFloor.putIfAbsent(element.floor, () => []).add(element);
      } else if (element.type == PlaceType.passage) {
        passagesByFloor.putIfAbsent(element.floor, () => []).add(element);
      }
    }

    String edgeKey(String a, String b) =>
        (a.compareTo(b) <= 0) ? '$a|$b' : '$b|$a';

    for (final entry in roomsByFloor.entries) {
      final passages = passagesByFloor[entry.key];
      if (passages == null || passages.isEmpty) continue;

      for (final room in entry.value) {
        CachedSData? closest;
        double bestDistance = double.infinity;

        for (final passage in passages) {
          final delta = room.position - passage.position;
          final distance = delta.dx * delta.dx + delta.dy * delta.dy;
          if (distance < bestDistance) {
            bestDistance = distance;
            closest = passage;
          }
        }

        if (closest == null) continue;
        final key = edgeKey(room.id, closest.id);
        if (existingEdgeKeys.add(key)) {
          edgeBucket.add({room.id, closest.id});
          changed = true;
        }
      }
    }

    if (changed) {
      _graphNodePositionCacheByFloor.clear();
      _edgeCacheByFloor.clear();
      notifyListeners();
    }
  }
}
