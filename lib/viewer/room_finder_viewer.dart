import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:test_project/room_editor/room_finder_app_editor.dart';
import 'package:test_project/models/room_finder_models.dart';
import 'package:test_project/viewer/interactive_screen.dart';
import 'passage_painter.dart';
import 'scroll_physics.dart';

part 'interaction_handler.dart';
part 'building_sync.dart';
part 'view_builders.dart';

enum CustomViewMode { editor, finder }

abstract class CustomView extends ConsumerStatefulWidget {
  const CustomView({super.key, required this.mode});

  final CustomViewMode mode;
}

mixin InteractiveImageMixin<T extends CustomView> on ConsumerState<T> {
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

  CachedSData? _pendingFocusElement;
  bool _suppressClearOnPageChange = false;

  bool get canSwipeFloors {
    final scale = transformationController.value.getMaxScaleOnAxis();
    final canSwipeWhileConnectingElevator =
        isConnecting && (connectingStart?.type == PlaceType.elevator);
    return !isDragging &&
        (!isConnecting || canSwipeWhileConnectingElevator) &&
        scale <= 1.05;
  }

  PlaceType currentType = PlaceType.room;
  final TransformationController transformationController =
      TransformationController();
  final double minScale = 0.8;
  final double maxScale = 8.0;

  @override
  void dispose() {
    transformationController.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int pageIndex) =>
      handlePageChangedLogic(this, pageIndex, ref);

  void onTapDetected(Offset position) =>
      handleTapDetectedLogic(this, position);

  void _ensureActiveBuildingSynced() =>
      ensureActiveBuildingSyncedLogic(this, ref);

  void syncToBuilding(BuildingSnapshot snapshot, {CachedSData? focusElement}) =>
      syncToBuildingLogic(this, ref, focusElement: focusElement);

  void handleMarkerTap(CachedSData sData, bool isSelected) =>
      handleMarkerTapLogic(this, sData, isSelected);

  void handleMarkerDragEnd(Offset position, bool isSelected) =>
      handleMarkerDragEndLogic(this, position, isSelected, ref);

  ScrollPhysics _pagePhysics = const NeverScrollableScrollPhysics();

  @override
  void initState() {
    super.initState();
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
        child: Listener(
          child: Builder(
          builder: (context) {
            final snap = ref.watch(activeBuildingProvider);
            _ensureActiveBuildingSynced();

            return Listener(
              child: PageView.builder(
                controller: pageController,
                scrollDirection: Axis.vertical,
                physics: _pagePhysics,
                itemCount: snap.floorCount,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, pageIndex) {
                  final int floor = snap.floorCount - pageIndex;

                  return _FloorPageView(
                    self: this,
                    floor: floor,
                  );
                },
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}
