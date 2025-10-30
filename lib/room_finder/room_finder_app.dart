import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:test_project/models/room_finder_models.dart';
import 'package:test_project/viewer/room_finder_viewer.dart';
import 'package:test_project/services/path_finder_logic.dart';
import 'package:test_project/services/building_data_loader.dart';
import 'detail_screen.dart';
import 'entrance_selector.dart';
import 'search_screen.dart';

class FinderView extends CustomView {
  const FinderView({super.key}) : super(mode: CustomViewMode.finder);

  @override
  ConsumerState<FinderView> createState() => _FinderViewState();
}

class _FinderViewState extends ConsumerState<FinderView>
    with InteractiveImageMixin<FinderView> {
  bool _isSearchMode = true;
  bool _needsNavigationOnBuild = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  BuildingRoomInfo? _selectedRoomInfo;
  String? _currentBuildingRoomId;

  @override
  void initState() {
    super.initState();
    final active = ref.read(activeBuildingProvider);
    pageController = PageController(
      initialPage: active.floorCount - currentFloor,
    );
    activeBuildingId = active.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rooms = ref.read(buildingRoomInfosProvider);
      if (rooms.isEmpty) {
        loadBuildingData(ref);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    ActiveBuildingNotifier notifier,
    BuildingRoomInfo info, {
    bool switchToDetail = false,
  }) {
    final wasSearchMode = _isSearchMode;
    notifier.setActiveBuilding(info.buildingId);

    ref.read(activeRouteProvider.notifier).clearActiveRouteNodes();
    if (switchToDetail) {
      FocusScope.of(context).unfocus();
    }

    final bool needsNav = switchToDetail && wasSearchMode;

    setState(() {
      if (switchToDetail) {
        _isSearchMode = false;
      }
      _selectedRoomInfo = info;
      _currentBuildingRoomId = info.room.id;
      if (needsNav) {
        _needsNavigationOnBuild = true;
      }
    });
  }

  void _returnToSearch() {
    FocusScope.of(context).unfocus();
    ref.read(activeRouteProvider.notifier).clearActiveRouteNodes();
    setState(() {
      _isSearchMode = true;
      _selectedRoomInfo = null;
      _currentBuildingRoomId = null;
      selectedElement = null;
      tapPosition = null;
    });
  }

  CachedSData? _resolveNavigationTarget() {
    final active = ref.read(activeBuildingProvider);
    final selected = selectedElement;
    if (selected != null) {
      final candidate = _findElementById(active, selected.id);
      if (candidate != null) {
        final activeRoute = ref.read(activeRouteProvider);
        final bool isRouteStart =
            activeRoute.isNotEmpty && activeRoute.first.id == candidate.id;
        if (!isRouteStart || _selectedRoomInfo == null) {
          return candidate;
        }
      }
    }
    final info = _selectedRoomInfo;
    if (info == null) return null;
    return _findElementById(active, info.room.id);
  }

  CachedSData? _findElementById(BuildingSnapshot snapshot, String id) {
    for (final e in snapshot.elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _focusEntrance(CachedSData entrance) {
    final active = ref.read(activeBuildingProvider);
    syncToBuilding(active, focusElement: entrance);
    if (!mounted) return;
    setState(() {
      selectedElement = entrance;
      tapPosition = entrance.position;
    });
  }

  Future<void> _startNavigation() async {
    final active = ref.read(activeBuildingProvider);
    final targetElement = _resolveNavigationTarget();
    if (targetElement == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目的地が選択されていません。')));
      return;
    }

    if (targetElement.type == PlaceType.room && mounted) {
      setState(() {
        _selectedRoomInfo = BuildingRoomInfo(
          buildingId: active.id,
          buildingName: active.name,
          room: targetElement,
        );
        _currentBuildingRoomId = targetElement.id;
      });
    }

    final entrances = active.elements
        .where((e) => e.type == PlaceType.entrance)
        .toList();
    if (entrances.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("この建物に入口が見つかりません。")));
      return;
    }

    CachedSData? startNode;
    if (entrances.length == 1) {
      startNode = entrances.first;
      _focusEntrance(startNode);
    } else {
      final initial = entrances.first;
      _focusEntrance(initial);
      startNode = await showEntranceSelector(
        context: context,
        entrances: entrances,
        initialId: initial.id,
        onFocus: (focusEntrance) => _focusEntrance(focusEntrance),
      );
    }
    if (startNode == null) return;

    final pathfinder = Pathfinder();
    final routeNodes = pathfinder.findPathFromSnapshot(
      active,
      startNode.id,
      targetElement.id,
    );

    if (routeNodes.isEmpty) {
      ref.read(activeRouteProvider.notifier).clearActiveRouteNodes();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ルートが見つかりません。')));
    } else {
      ref.read(activeRouteProvider.notifier).setActiveRouteNodes(routeNodes);
    }

    _focusEntrance(startNode);
  }

  @override
  void onTapDetected(Offset position) {
    if (ref.read(activeRouteProvider).isNotEmpty) {
      return;
    }
    setState(() {
      tapPosition = position;
      selectedElement = null;
    });
  }

  @override
  void syncToBuilding(BuildingSnapshot snapshot, {CachedSData? focusElement}) {
    super.syncToBuilding(snapshot, focusElement: focusElement);
    if (_selectedRoomInfo == null) return;
    final selectedStillExists =
        _findElementById(snapshot, _selectedRoomInfo!.room.id) != null;
    final hasMismatch =
        snapshot.id != _selectedRoomInfo!.buildingId || !selectedStillExists;
    if (hasMismatch) {
      setState(() {
        _isSearchMode = true;
        _selectedRoomInfo = null;
        _currentBuildingRoomId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(buildingRepositoryProvider);
    final isLoading = repo.isLoading;

    final allRooms = ref.watch(buildingRoomInfosProvider);
    final activeBuilding = ref.watch(activeBuildingProvider);
    if (_needsNavigationOnBuild) {
      _needsNavigationOnBuild = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final currentActiveBuilding = ref.read(activeBuildingProvider);
        final selectedRoom = _findElementById(
          currentActiveBuilding,
          _selectedRoomInfo!.room.id,
        );

        if (selectedRoom == null) {
          _returnToSearch();
          return;
        }

        syncToBuilding(currentActiveBuilding, focusElement: selectedRoom);

        _startNavigation();
      });
    }

    final shouldShowSearch = _isSearchMode || _selectedRoomInfo == null;

    final content = shouldShowSearch
        ? FinderSearchContent(
            isLoading: isLoading,
            searchController: _searchController,
            searchFocusNode: _searchFocusNode,
            results: _filterRooms(
              _sortedRooms(List<BuildingRoomInfo>.from(allRooms)),
            ),
            onQueryChanged: (_) => setState(() {}),
            onClearQuery: () {
              _searchController.clear();
              setState(() {});
            },
            onRoomTap: (info) => _activateRoom(
              ref.read(activeBuildingProvider.notifier),
              info,
              switchToDetail: true,
            ),
          )
        : () {
            final inSameBuilding = allRooms
                .where((info) => info.buildingId == activeBuilding.id)
                .toList();
            final hasValue = inSameBuilding.any(
              (info) => info.room.id == _currentBuildingRoomId,
            );
            final dropdownValue = hasValue ? _currentBuildingRoomId : null;

            return FinderDetailContent(
              currentFloor: currentFloor,
              dropdownValue: dropdownValue,
              roomsInBuilding: inSameBuilding,
              selectedRoomInfo: _selectedRoomInfo,
              onRoomSelected: (value) {
                if (value == null || inSameBuilding.isEmpty) return;
                final match = inSameBuilding.firstWhere(
                  (info) => info.room.id == value,
                  orElse: () => _selectedRoomInfo!,
                );
                _activateRoom(ref.read(activeBuildingProvider.notifier), match);
              },
              onReturnToSearch: _returnToSearch,
              interactiveImage: buildInteractiveImage(),
              selectedElementLabel: _selectedElementLabel(
                activeBuilding,
              ),
              onStartNavigation: isLoading ? null : _startNavigation,
            );
          }();

    return Stack(
      children: [
        content,
        if (shouldShowSearch)
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              heroTag: 'focus_search',
              onPressed: () =>
                  FocusScope.of(context).requestFocus(_searchFocusNode),
              backgroundColor: Colors.green,
              child: const Icon(Icons.search),
              tooltip: '検索ボックスにフォーカス',
            ),
          ),
      ],
    );
  }

  String _selectedElementLabel(BuildingSnapshot snapshot) {
    final target = _resolveNavigationTarget();
    if (target != null) {
      return target.name.isNotEmpty ? target.name : target.id;
    }
    if (_selectedRoomInfo != null) {
      final r = _selectedRoomInfo!.room;
      return r.name.isNotEmpty ? r.name : r.id;
    }
    return '-';
  }
}
