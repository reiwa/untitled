import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';

const String kDraftBuildingId = '__editor_draft__';

class BuildingSnapshot {
  BuildingSnapshot({
    required this.id,
    required this.name,
    required this.floorCount,
    required this.imagePattern,
    required this.elements,
    required this.passages,
  });

  final String id;
  final String name;
  final int floorCount;
  final String imagePattern;
  final List<CachedSData> elements;
  final List<CachedPData> passages;

  Iterable<CachedSData> get rooms =>
      elements.where((element) => element.type == PlaceType.room);

  BuildingSnapshot copyWith({
    String? id,
    String? name,
    int? floorCount,
    String? imagePattern,
    List<CachedSData>? elements,
    List<CachedPData>? passages,
  }) {
    return BuildingSnapshot(
      id: id ?? this.id,
      name: name ?? this.name,
      floorCount: floorCount ?? this.floorCount,
      imagePattern: imagePattern ?? this.imagePattern,
      elements: elements ?? this.elements,
      passages: passages ?? this.passages,
    );
  }
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

final buildingRepositoryProvider = AsyncNotifierProvider<BuildingRepository, Map<String, BuildingSnapshot>>(
  BuildingRepository.new,
);

class BuildingRepository extends AsyncNotifier<Map<String, BuildingSnapshot>> {
  @override
  Future<Map<String, BuildingSnapshot>> build() async {
    return <String, BuildingSnapshot>{};
  }

  void loadBuildingsFromJson(String raw) {
    final parsed = _parseBuildingsJson(raw);
    state = AsyncData(parsed);
  }

  void upsert(BuildingSnapshot snapshot) {
    final current = state.asData?.value ?? <String, BuildingSnapshot>{};
    state = AsyncData({
      ...current,
      snapshot.id: snapshot,
    });
  }

  void remove(String id) {
    final current = state.asData?.value ?? <String, BuildingSnapshot>{};
    if (!current.containsKey(id)) return;
    final next = Map<String, BuildingSnapshot>.from(current)..remove(id);
    state = AsyncData(next);
  }

  BuildingSnapshot? getById(String id) {
    final current = state.asData?.value;
    if (current == null) return null;
    return current[id];
  }

  bool get hasDraft => (state.asData?.value ?? const {}).containsKey(kDraftBuildingId);

  String? get firstNonDraftBuildingId {
    final current = state.asData?.value ?? const {};
    for (final entry in current.entries) {
      if (entry.key == kDraftBuildingId) continue;
      return entry.key;
    }
    return null;
  }

  List<BuildingRoomInfo> getAllRoomInfos() {
    final current = state.asData?.value ?? const {};
    final result = <BuildingRoomInfo>[];
    for (final snapshot in current.values) {
      if (snapshot.id == kDraftBuildingId) continue;
      for (final room in snapshot.rooms) {
        result.add(BuildingRoomInfo(
          buildingId: snapshot.id,
          buildingName: snapshot.name,
          room: room,
        ));
      }
    }
    return result;
  }

  Map<String, BuildingSnapshot> _parseBuildingsJson(String rawJson) {
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
      return <String, BuildingSnapshot>{};
    }

    final result = <String, BuildingSnapshot>{};
    int fallbackIndex = 0;
    for (final dynamic node in buildingNodes) {
      if (node is! Map<String, dynamic>) continue;
      fallbackIndex += 1;
      final snapshot = _snapshotFromJson(node, fallbackIndex: fallbackIndex);
      result[snapshot.id] = snapshot;
    }
    return result;
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
        elements.add(CachedSData(
          id: id,
          name: elementName,
          position: position,
          floor: floor,
          type: placeType,
        ));
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
}

final activeBuildingProvider = NotifierProvider<ActiveBuildingNotifier, BuildingSnapshot>(
  ActiveBuildingNotifier.new,
);

class ActiveBuildingNotifier extends Notifier<BuildingSnapshot> {
  @override
  BuildingSnapshot build() {
    final repoValue = ref.watch(buildingRepositoryProvider).asData?.value ?? const <String, BuildingSnapshot>{};

    BuildingSnapshot? initial;
    for (final entry in repoValue.entries) {
      if (entry.key == kDraftBuildingId) continue;
      initial = entry.value;
      break;
    }
    initial ??= repoValue[kDraftBuildingId];

    return initial ??
        BuildingSnapshot(
          id: kDraftBuildingId,
          name: '新しい建物',
          floorCount: 1,
          imagePattern: '',
          elements: <CachedSData>[],
          passages: [CachedPData(edges: {})],
        );
  }

  void startNewBuildingDraft() {
    state = BuildingSnapshot(
      id: kDraftBuildingId,
      name: '新しい建物',
      floorCount: 1,
      imagePattern: '',
      elements: <CachedSData>[],
      passages: [CachedPData(edges: {})],
    );
  }

  void startDraftFromActive() {
    final src = state;
    final newPassages = [
      for (final p in src.passages)
        CachedPData(edges: p.edges.map((s) => Set<String>.from(s)).toSet()),
    ];
    state = BuildingSnapshot(
      id: kDraftBuildingId,
      name: src.name,
      floorCount: src.floorCount,
      imagePattern: src.imagePattern,
      elements: [
        for (final e in src.elements)
          CachedSData(
            id: e.id,
            name: e.name,
            position: e.position,
            floor: e.floor,
            type: e.type,
          ),
      ],
      passages: newPassages.isEmpty ? [CachedPData(edges: {})] : newPassages,
    );
  }

  void updateBuildingSettings({String? name, int? floors, String? pattern}) {
    state = state.copyWith(
      name: name ?? state.name,
      floorCount: floors ?? state.floorCount,
      imagePattern: pattern ?? state.imagePattern,
    );
  }

  void addSData(CachedSData data) {
    final next = [...state.elements, data];
    state = state.copyWith(elements: next);
  }

  void addData(List<CachedSData> data) {
    final next = [...state.elements, ...data];
    state = state.copyWith(elements: next);
  }

  void updateSData(CachedSData updatedData) {
    final idx = state.elements.indexWhere((e) => e.id == updatedData.id);
    if (idx < 0) return;
    final next = [...state.elements]..[idx] = updatedData;
    state = state.copyWith(elements: next);
  }

  void removeSData(CachedSData data) {
    final nextElements = [...state.elements]..removeWhere((e) => e.id == data.id);
    final nextPassages = _removeEdgesLinkedTo(state.passages, data.id);
    state = state.copyWith(elements: nextElements, passages: nextPassages);
  }

  void addPData(CachedPData data) {
    final next = [...state.passages, data];
    state = state.copyWith(passages: next);
  }

  void addEdge(String startId, String endId) {
    if (startId == endId) return;
    final edgeSet = {startId, endId};

    final passages = state.passages.isEmpty ? [CachedPData(edges: {})] : state.passages;
    final first = passages.first;
    final alreadyExists = first.edges.any((existing) => existing.containsAll(edgeSet));
    if (alreadyExists) return;

    final newFirst = CachedPData(edges: {...first.edges, edgeSet});
    final nextPassages = [newFirst, ...passages.skip(1)];
    state = state.copyWith(passages: nextPassages);
  }

  bool hasEdges(String passageId) {
    if (state.passages.isEmpty) return false;
    return state.passages.first.edges.any((set) => set.contains(passageId));
  }

  void rebuildRoomPassageEdges() {
    final passages = state.passages.isEmpty ? [CachedPData(edges: {})] : state.passages;

    final elementsById = {for (final e in state.elements) e.id: e};

    final cleanedPassages = passages
        .map((p) => CachedPData(
              edges: p.edges
                  .where((edge) {
                    if (edge.length != 2) return true;
                    final hasRoom = edge.any((id) => elementsById[id]?.type == PlaceType.room);
                    return !hasRoom;
                  })
                  .toSet(),
            ))
        .toList();

    final bucket = cleanedPassages.first.edges;
    final existingEdgeKeys = <String>{};
    for (final edge in bucket) {
      if (edge.length != 2) continue;
      final ids = edge.toList()..sort();
      existingEdgeKeys.add('${ids[0]}|${ids[1]}');
    }

    final roomsByFloor = <int, List<CachedSData>>{};
    final passagesByFloor = <int, List<CachedSData>>{};
    for (final e in state.elements) {
      if (e.type == PlaceType.room) {
        roomsByFloor.putIfAbsent(e.floor, () => []).add(e);
      } else if (e.type == PlaceType.passage) {
        passagesByFloor.putIfAbsent(e.floor, () => []).add(e);
      }
    }

    String edgeKey(String a, String b) => (a.compareTo(b) <= 0) ? '$a|$b' : '$b|$a';

    for (final entry in roomsByFloor.entries) {
      final floorPassages = passagesByFloor[entry.key];
      if (floorPassages == null || floorPassages.isEmpty) continue;

      for (final room in entry.value) {
        CachedSData? closest;
        double bestDist = double.infinity;
        for (final p in floorPassages) {
          final dx = room.position.dx - p.position.dx;
          final dy = room.position.dy - p.position.dy;
          final dist = dx * dx + dy * dy;
          if (dist < bestDist) {
            bestDist = dist;
            closest = p;
          }
        }
        if (closest == null) continue;
        final key = edgeKey(room.id, closest.id);
        if (existingEdgeKeys.add(key)) {
          bucket.add({room.id, closest.id});
        }
      }
    }

    final nextPassages = [
      CachedPData(edges: bucket),
      ...cleanedPassages.skip(1),
    ];
    state = state.copyWith(passages: nextPassages);
  }

  List<CachedPData> _removeEdgesLinkedTo(List<CachedPData> passages, String nodeId) {
    if (passages.isEmpty) return [CachedPData(edges: {})];
    final first = passages.first;
    final nextFirst = CachedPData(
      edges: first.edges.where((edge) => !edge.contains(nodeId)).toSet(),
    );
    return [nextFirst, ...passages.skip(1)];
  }

  void commitToRepository() {
    ref.read(buildingRepositoryProvider.notifier).upsert(state);
  }

  void setActiveBuilding(String buildingId) {
    final repo = ref.read(buildingRepositoryProvider);

    final snapshotMap = repo.asData?.value;
    if (snapshotMap == null) return;

    final targetSnapshot = snapshotMap[buildingId];
    if (targetSnapshot == null) return;

    state = targetSnapshot;
  }

  void startDraftForEditing(String buildingId) {
    final repo = ref.read(buildingRepositoryProvider);
    final snapshotMap = repo.asData?.value;
    final sourceSnapshot = snapshotMap?[buildingId];

    if (sourceSnapshot == null || buildingId == kDraftBuildingId) {
      return;
    }

    state = BuildingSnapshot(
      id: kDraftBuildingId,
      name: sourceSnapshot.name,
      floorCount: sourceSnapshot.floorCount,
      imagePattern: sourceSnapshot.imagePattern,
      elements: [
        for (final e in sourceSnapshot.elements) e.copyWith(),
      ],
      passages:
          [
            for (final p in sourceSnapshot.passages)
              CachedPData(
                edges: p.edges.map((s) => Set<String>.from(s)).toSet(),
              ),
          ].isEmpty
          ? [CachedPData(edges: {})]
          : [
              for (final p in sourceSnapshot.passages)
                CachedPData(
                  edges: p.edges.map((s) => Set<String>.from(s)).toSet(),
                ),
            ],
    );
  }

  String buildSnapshot() {
    final buffer = StringBuffer()
      ..writeln('{')
      ..writeln('            "building_name": "${state.name}",')
      ..writeln('            "floor_count": ${state.floorCount},')
      ..writeln('            "image_pattern": "${state.imagePattern}",')
      ..writeln('            "elements": [');

    for (var i = 0; i < state.elements.length; i++) {
      final element = state.elements[i];
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
      if (i != state.elements.length - 1) buffer.write(',');
      buffer.writeln();
    }

    buffer
      ..writeln('            ],')
      ..writeln('            "edges": [');

    final allEdges = state.passages
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
}

final graphNodePositionsProvider = Provider.family<Map<String, Offset>, int>((ref, floor) {
  final snap = ref.watch(activeBuildingProvider);
  return {
    for (final s in snap.elements.where((e) => e.type.isGraphNode && e.floor == floor)) s.id: s.position,
  };
});

final graphEdgesProvider = Provider.family<List<Edge>, int>((ref, floor) {
  final positions = ref.watch(graphNodePositionsProvider(floor));
  final snap = ref.watch(activeBuildingProvider);
  final edges = <Edge>[];
  for (final p in snap.passages) {
    for (final set in p.edges) {
      if (set.length != 2) continue;
      final ids = set.toList();
      final a = positions[ids[0]];
      final b = positions[ids[1]];
      if (a != null && b != null) {
        edges.add(Edge(start: a, end: b));
      }
    }
  }
  return edges;
});

final activeRouteProvider = NotifierProvider<ActiveRouteNotifier, List<CachedSData>>(
  ActiveRouteNotifier.new,
);

class ActiveRouteNotifier extends Notifier<List<CachedSData>> {
  @override
  List<CachedSData> build() => <CachedSData>[];

  void setActiveRouteNodes(List<CachedSData> nodes) {
    state = List<CachedSData>.from(nodes);
  }

  void clearActiveRouteNodes() {
    if (state.isEmpty) return;
    state = <CachedSData>[];
  }
}

final activeRouteSegmentsProvider = Provider<List<RouteSegment>>((ref) {
  final nodes = ref.watch(activeRouteProvider);
  final segments = <RouteSegment>[];
  for (var i = 0; i < nodes.length - 1; i++) {
    segments.add(RouteSegment(from: nodes[i], to: nodes[i + 1]));
  }
  return segments;
});

final buildingRoomInfosProvider = Provider<List<BuildingRoomInfo>>((ref) {
  final repo = ref.watch(buildingRepositoryProvider);
  return repo.maybeWhen(
    data: (map) {
      final list = <BuildingRoomInfo>[];
      for (final snapshot in map.values) {
        if (snapshot.id == kDraftBuildingId) continue;
        for (final room in snapshot.rooms) {
          list.add(BuildingRoomInfo(
            buildingId: snapshot.id,
            buildingName: snapshot.name,
            room: room,
          ));
        }
      }
      return list;
    },
    orElse: () => <BuildingRoomInfo>[],
  );
});
