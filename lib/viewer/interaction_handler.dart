part of 'room_finder_viewer.dart';

void handleTapDetectedLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  Offset position,
) {
  host.setState(() {
    host.selectedElement = null;
  });
}

void updateEditorControllersPosition<T extends CustomView>(
  InteractiveImageMixin<T> host,
  Offset position,
) {
  if (host is! EditorControllerHost) return;
  final editor = host as EditorControllerHost;
  editor.xController.text = position.dx.toStringAsFixed(0);
  editor.yController.text = position.dy.toStringAsFixed(0);
}

void handleMarkerTapLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  CachedSData sData,
  bool isSelected,
) {
  if (host.isConnecting) {
    handleTapDetectedLogic(host, sData.position);
    return;
  }
  final newSelected = isSelected ? null : sData;
  host.setState(() {
    host.selectedElement = newSelected;
    if (newSelected != null) {
      host.tapPosition = newSelected.position;
      if (host is EditorControllerHost) {
        final editor = host as EditorControllerHost;
        editor.nameController.text = newSelected.name;
      }
      updateEditorControllersPosition(host, newSelected.position);
    } else {
      host.tapPosition = null;
      if (host is EditorControllerHost) {
        final editor = host as EditorControllerHost;
        editor.nameController.clear();
        editor.xController.clear();
        editor.yController.clear();
      }
    }
  });
}

void handleMarkerDragEndLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  Offset position,
  bool isSelected,
  WidgetRef ref,
) {
  if (!isSelected || host.selectedElement == null) {
    host.setState(() {
      host.isDragging = false;
    });
    return;
  }
  final updatedData = host.selectedElement!.copyWith(position: position);
  host.setState(() {
    host.isDragging = false;
    host.selectedElement = updatedData;
    host.tapPosition = position;
  });
  updateEditorControllersPosition(host, position);
  ref.read(activeBuildingProvider.notifier).updateSData(updatedData);
}
