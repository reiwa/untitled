part of 'room_finder_viewer.dart';

void handlePageChangedLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  int pageIndex,
  WidgetRef ref,
) {
  final active = ref.read(activeBuildingProvider);
  host.setState(() {
    host._currentFloor = active.floorCount - pageIndex;
    host.activeBuildingId = active.id;

    if (!host._suppressClearOnPageChange) {
      host.tapPosition = null;
      host.selectedElement = null;
      if (host is EditorControllerHost) {
        final editor = host as EditorControllerHost;
        editor.nameController.clear();
        editor.xController.clear();
        editor.yController.clear();
      }
    }

    host.isDragging = false;
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    applyPendingFocusIfAnyLogic(host);
  });
}

void ensureActiveBuildingSyncedLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  WidgetRef ref,
) {
  final active = ref.read(activeBuildingProvider);

  if (host.widget.mode == CustomViewMode.editor &&
      active.id != kDraftBuildingId) {
    if (host._pendingContainerSync) return;
    host._pendingContainerSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted) return;
      ref.read(activeBuildingProvider.notifier).startDraftFromActive();
      host._pendingContainerSync = false;
    });
    return;
  }

  if (host.widget.mode == CustomViewMode.finder &&
      (active.id == kDraftBuildingId)) {
    final fallbackId = ref.read(buildingRepositoryProvider.notifier).firstNonDraftBuildingId;
    if (fallbackId != null &&
        fallbackId != active.id &&
        !host._pendingContainerSync) {
      host._pendingContainerSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!host.mounted) return;
        ref.read(activeBuildingProvider.notifier).setActiveBuilding(fallbackId);
        host._pendingContainerSync = false;
      });
    }
    return;
  }

  final buildingMismatch =
      active.id != host.activeBuildingId;
  final floorOutOfRange =
      host.currentFloor > active.floorCount;

  if ((buildingMismatch || floorOutOfRange) && !host._pendingContainerSync) {
    host._pendingContainerSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted) return;
      syncToBuildingLogic(host, ref, focusElement: null);
      host._pendingContainerSync = false;
    });
  }
}

void syncToBuildingLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  WidgetRef ref, {
  CachedSData? focusElement,
}) {
  final active = ref.read(activeBuildingProvider);
  final targetFloor = focusElement?.floor ?? 1;
  final clampedFloor = targetFloor < 1
      ? 1
      : (targetFloor > active.floorCount
          ? active.floorCount
          : targetFloor);
  final pageIndex = active.floorCount - clampedFloor;

  final needsFloorChange = clampedFloor != host._currentFloor;

  host.setState(() {
    host.activeBuildingId = active.id;
    host._currentFloor = clampedFloor;

    if (needsFloorChange && focusElement != null) {
      host._pendingFocusElement = focusElement;
      host._suppressClearOnPageChange = true;
      host.tapPosition = null;
    } else {
      host.tapPosition = focusElement?.position;
      host.selectedElement = focusElement;
      host.transformationController.value = Matrix4.identity();
    }

    host.isDragging = false;
    host.isConnecting = false;
    host.connectingStart = null;
    host.previewPosition = null;
  });

  if (needsFloorChange) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.pageController.hasClients) {
        host.pageController.jumpToPage(pageIndex);
      } else {
        applyPendingFocusIfAnyLogic(host);
      }
    });
  }
}

void applyPendingFocusIfAnyLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
) {
  if (host._pendingFocusElement != null) {
    final focus = host._pendingFocusElement!;
    host.setState(() {
      host.selectedElement = focus;
      host.tapPosition = focus.position;
      host.transformationController.value = Matrix4.identity();
    });
  }
  host._pendingFocusElement = null;
  host._suppressClearOnPageChange = false;
}
