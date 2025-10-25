import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:test_project/RoomFinderAppShared.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:math';

class _AStarNode {
  final String id;
  double fScore;

  _AStarNode({required this.id, required this.fScore});
}

class Pathfinder {
  static const double _floorChangeCost = 1.0;

  double _heuristic(CachedSData a, CachedSData b) {
    final posDistance = (a.position - b.position).distance;
    final floorDistance = (a.floor - b.floor).abs() * _floorChangeCost;
    return posDistance + floorDistance;
  }

  double _distanceBetween(CachedSData a, CachedSData b) {
    return _heuristic(a, b);
  }

  CachedSData _findClosestGraphNode(
    List<CachedSData> allGraphNodes,
    CachedSData targetRoom,
  ) {
    Iterable<CachedSData> nodesOnSameFloor = allGraphNodes.where(
      (node) => node.floor == targetRoom.floor,
    );

    if (nodesOnSameFloor.isEmpty) {
      nodesOnSameFloor = allGraphNodes;
    }

    CachedSData? closestNode;
    double minDistance = double.infinity;

    for (final node in nodesOnSameFloor) {
      final dist = _heuristic(node, targetRoom);
      if (dist < minDistance) {
        minDistance = dist;
        closestNode = node;
      }
    }
    return closestNode!;
  }

  Iterable<String> _getNeighbors(BDataContainer container, String nodeId) {
    final neighbors = <String>{};
    for (final pData in container.cachedPDataList) {
      for (final edge in pData.edges) {
        if (edge.contains(nodeId)) {
          neighbors.addAll(edge.where((id) => id != nodeId));
        }
      }
    }
    return neighbors;
  }

  List<CachedSData> findPath(
    BDataContainer container,
    String startNodeId,
    String targetRoomId,
  ) {
    final allGraphNodes = container.cachedSDataList
        .where((e) => e.type.isGraphNode)
        .toList();
    final nodeMap = {for (var n in allGraphNodes) n.id: n};

    final startNode = nodeMap[startNodeId];
    final targetRoom = container.findElementById(targetRoomId);

    if (startNode == null || targetRoom == null) {
      return [];
    }

    final aStarTargetNode = _findClosestGraphNode(allGraphNodes, targetRoom);

    final openSet = <_AStarNode>[];
    final closedSet = <String>{};
    final cameFrom = <String, String>{};
    final gScores = <String, double>{startNode.id: 0};
    final fScores = <String, double>{
      startNode.id: _heuristic(startNode, aStarTargetNode),
    };

    openSet.add(_AStarNode(id: startNode.id, fScore: fScores[startNode.id]!));

    while (openSet.isNotEmpty) {
      openSet.sort((a, b) => a.fScore.compareTo(b.fScore));
      final current = openSet.removeAt(0);
      final currentNode = nodeMap[current.id]!;

      if (current.id == aStarTargetNode.id) {
        return _reconstructPath(cameFrom, current.id, nodeMap, targetRoom);
      }

      closedSet.add(current.id);

      for (final neighborId in _getNeighbors(container, current.id)) {
        if (closedSet.contains(neighborId) ||
            !nodeMap.containsKey(neighborId)) {
          continue;
        }

        final neighborNode = nodeMap[neighborId]!;
        final tentativeGScore =
            gScores[current.id]! + _distanceBetween(currentNode, neighborNode);

        if (tentativeGScore < (gScores[neighborId] ?? double.infinity)) {
          cameFrom[neighborId] = current.id;
          gScores[neighborId] = tentativeGScore;
          fScores[neighborId] =
              tentativeGScore + _heuristic(neighborNode, aStarTargetNode);

          if (!openSet.any((node) => node.id == neighborId)) {
            openSet.add(
              _AStarNode(id: neighborId, fScore: fScores[neighborId]!),
            );
          }
        }
      }
    }

    return [];
  }

  List<CachedSData> _reconstructPath(
    Map<String, String> cameFrom,
    String currentId,
    Map<String, CachedSData> nodeMap,
    CachedSData targetRoom,
  ) {
    final pathNodes = <CachedSData>[];
    String current = currentId;

    while (cameFrom.containsKey(current)) {
      pathNodes.add(nodeMap[current]!);
      current = cameFrom[current]!;
    }
    pathNodes.add(nodeMap[current]!);

    final orderedPath = pathNodes.reversed.toList();
    orderedPath.add(targetRoom);

    return orderedPath;
  }
}

class FinderView extends CustomView {
  const FinderView({super.key}) : super(mode: CustomViewMode.finder);

  @override
  State<FinderView> createState() => _FinderViewState();
}

class _FinderViewState extends State<FinderView>
    with InteractiveImageMixin<FinderView> {
  bool _isLoading = true;
  bool _isSearchMode = true;
  static const String _buildingDataAssetPath = 'assets/data/buildings.json';

  final TextEditingController _searchController = TextEditingController();
  BuildingRoomInfo? _selectedRoomInfo;
  String? _currentBuildingRoomId;

  @override
  void initState() {
    super.initState();
    final bDataContainer = context.read<BDataContainer>();
    pageController = PageController(
      initialPage: bDataContainer.floorCount - currentFloor,
    );
    activeBuildingId = bDataContainer.activeBuildingId;
    _loadBuildingData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBuildingData() async {
    try {
      final raw = await rootBundle.loadString(_buildingDataAssetPath);
      if (!mounted) return;
      final container = context.read<BDataContainer>();
      container.loadBuildingsFromJson(raw);
    } catch (error) {
      debugPrint('Failed to load building data: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<BuildingRoomInfo> _sortedRooms(List<BuildingRoomInfo> rooms) {
    rooms.sort((a, b) {
      final buildingCompare = a.buildingName.compareTo(b.buildingName);
      if (buildingCompare != 0) return buildingCompare;
      final aName = a.room.name.isEmpty ? a.room.id : a.room.name;
      final bName = b.room.name.isEmpty ? b.room.id : b.room.name;
      final roomCompare = aName.compareTo(bName);
      if (roomCompare != 0) return roomCompare;
      return a.room.id.compareTo(b.room.id);
    });
    return rooms;
  }

  List<BuildingRoomInfo> _filterRooms(List<BuildingRoomInfo> rooms) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return rooms;
    return rooms.where((info) {
      final roomName = info.room.name.toLowerCase();
      final buildingName = info.buildingName.toLowerCase();
      final roomId = info.room.id.toLowerCase();
      return roomName.contains(query) ||
          buildingName.contains(query) ||
          roomId.contains(query);
    }).toList();
  }

  void _activateRoom(
    BDataContainer container,
    BuildingRoomInfo info, {
    bool switchToDetail = false,
  }) {
    container.setActiveBuilding(info.buildingId);
    final selectedRoom = container.findElementById(info.room.id);
    if (selectedRoom == null) return;
    container.clearActiveRouteNodes();
    if (switchToDetail) {
      FocusScope.of(context).unfocus();
    }
    setState(() {
      if (switchToDetail) {
        _isSearchMode = false;
      }
      _selectedRoomInfo = info;
      _currentBuildingRoomId = info.room.id;
    });
    syncToBuilding(container, focusElement: selectedRoom);
  }

  void _returnToSearch(BDataContainer container) {
    FocusScope.of(context).unfocus();
    container.clearActiveRouteNodes();
    setState(() {
      _isSearchMode = true;
      _selectedRoomInfo = null;
      _currentBuildingRoomId = null;
      selectedElement = null;
      tapPosition = null;
    });
  }

  Future<void> _startNavigation(BDataContainer container) async {
    final roomInfo = _selectedRoomInfo;
    if (roomInfo == null) return;
    final targetRoom = container.findElementById(roomInfo.room.id);
    if (targetRoom == null) return;

    final entrances = container.cachedSDataList
        .where((e) => e.type == PlaceType.entrance)
        .toList();

    if (entrances.isEmpty) {
      debugPrint("この建物に入口が見つかりません。");
      return;
    }

    CachedSData? startNode;
    if (entrances.length == 1) {
      startNode = entrances.first;
    } else {
      startNode = await _showEntranceSelectionSheet(entrances, container);
    }
    if (startNode == null) return;

    final pathfinder = Pathfinder();
    final routeNodes = pathfinder.findPath(
      container,
      startNode.id,
      targetRoom.id,
    );

    if (routeNodes.isEmpty) {
      container.clearActiveRouteNodes();
      debugPrint('ルートが見つかりません。');
    } else {
      container.setActiveRouteNodes(routeNodes);
    }

    syncToBuilding(container, focusElement: startNode);
    if (!mounted) return;
    setState(() {
      selectedElement = startNode;
      tapPosition = startNode!.position;
    });
  }

  Future<CachedSData?> _showEntranceSelectionSheet(
    List<CachedSData> entrances,
    BDataContainer container,
  ) {
    if (entrances.isEmpty) return Future.value(null);
    final initialId = entrances.first.id;
    return showGeneralDialog<CachedSData>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'entrance_selector',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        String? selectedId = initialId;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: 12,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '入口を選択',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: min(entrances.length * 56.0, 280),
                          child: ListView.builder(
                            itemCount: entrances.length,
                            itemBuilder: (context, index) {
                              final entrance = entrances[index];
                              final title = entrance.name.isEmpty
                                  ? entrance.id
                                  : entrance.name;
                              return RadioListTile<String>(
                                dense: true,
                                value: entrance.id,
                                groupValue: selectedId,
                                title: Text(
                                  title,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setSheetState(() => selectedId = value);
                                  final focusEntrance = entrances.firstWhere(
                                    (e) => e.id == value,
                                  );
                                  syncToBuilding(
                                    container,
                                    focusElement: focusEntrance,
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    selectedElement = focusEntrance;
                                    tapPosition = focusEntrance.position;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(null),
                                child: const Text(
                                  'キャンセル',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final selected = entrances.firstWhere(
                                    (e) => e.id == selectedId,
                                    orElse: () => entrances.first,
                                  );
                                  Navigator.of(dialogContext).pop(selected);
                                },
                                child: const Text(
                                  '確定',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
    );
  }

  String _selectedElementLabel(BDataContainer container) {
    final el = selectedElement;
    if (el != null) {
      final displayName = (el.name.isNotEmpty) ? el.name : el.id;
      return displayName;
    } else if (_selectedRoomInfo != null) {
      final r = _selectedRoomInfo!.room;
      return (r.name.isNotEmpty) ? r.name : r.id;
    } else {
      return '-';
    }
  }

  Widget _buildSearchContent(
    BDataContainer container,
    List<BuildingRoomInfo> allRooms,
  ) {
    final results = _filterRooms(allRooms);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            enabled: !_isLoading,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '部屋を検索',
              labelStyle: const TextStyle(fontSize: 14),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : results.isEmpty
              ? const Center(
                  child: Text('該当する部屋がありません', style: TextStyle(fontSize: 13)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final info = results[index];
                    final title = info.room.name.isEmpty
                        ? info.room.id
                        : info.room.name;
                    return ListTile(
                      dense: true,
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        info.buildingName,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: Text(
                        '${info.room.floor}階',
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () =>
                          _activateRoom(container, info, switchToDetail: true),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailContent(
    BDataContainer container,
    List<BuildingRoomInfo> allRooms,
  ) {
    final roomsInBuilding = _selectedRoomInfo == null
        ? <BuildingRoomInfo>[]
        : allRooms
              .where((info) => info.buildingId == _selectedRoomInfo!.buildingId)
              .toList();
    final hasValue = roomsInBuilding.any(
      (info) => info.room.id == _currentBuildingRoomId,
    );
    final dropdownValue = hasValue ? _currentBuildingRoomId : null;

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Text(
                  '$currentFloor階',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const VerticalDivider(thickness: 1, indent: 8, endIndent: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dropdownValue,
                      hint: const Text('部屋を選択', style: TextStyle(fontSize: 13)),
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      onChanged: (value) {
                        if (value == null || roomsInBuilding.isEmpty) return;
                        final match = roomsInBuilding.firstWhere(
                          (info) => info.room.id == value,
                          orElse: () => _selectedRoomInfo!,
                        );
                        _activateRoom(container, match);
                      },
                      items: roomsInBuilding.map((info) {
                        final title = info.room.name.isEmpty
                            ? info.room.id
                            : info.room.name;
                        return DropdownMenuItem<String>(
                          value: info.room.id,
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _returnToSearch(container),
                  child: const Text('検索へ戻る', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
        buildInteractiveImage(),
        const SizedBox(height: 4),
        Container(height: 2, color: Colors.grey.shade300),
        const SizedBox(height: 4),

        SizedBox(
          height: 78,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedRoomInfo != null
                            ? '建物: ${_selectedRoomInfo!.buildingName}'
                            : '建物: -',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _selectedElementLabel(container),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: (_selectedRoomInfo == null || _isLoading)
                      ? null
                      : () => _startNavigation(container),
                  child: const Text(
                    'ナビゲーションを開始する!',
                    style: TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void onTapDetected(Offset position) {
    final container = context.read<BDataContainer>();
    if (container.activeRouteNodes.isNotEmpty) {
      return;
    }

    setState(() {
      tapPosition = position;
      selectedElement = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BDataContainer>(
      builder: (context, container, child) {
        final allRooms = _sortedRooms(container.getAllRoomInfos());
        final shouldShowSearch = _isSearchMode || _selectedRoomInfo == null;
        return Container(
          child: shouldShowSearch
              ? _buildSearchContent(container, allRooms)
              : _buildDetailContent(container, allRooms),
        );
      },
    );
  }
}
