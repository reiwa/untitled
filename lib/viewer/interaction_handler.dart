part of 'room_finder_viewer.dart';

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
  WidgetRef ref,
) {
  ref.read(interactiveImageProvider.notifier).handleMarkerTap(sData, isSelected);

  final imgState = ref.read(interactiveImageProvider);
  final newSelected = imgState.selectedElement;

  if (host is EditorControllerHost) {
    final editor = host as EditorControllerHost;
    if (newSelected != null) {
      editor.nameController.text = newSelected.name;
      updateEditorControllersPosition(host, newSelected.position);
    } else {
      editor.nameController.clear();
      editor.xController.clear();
      editor.yController.clear();
    }
  }
}

void handleMarkerDragEndLogic<T extends CustomView>(
  InteractiveImageMixin<T> host,
  Offset position,
  bool isSelected,
  WidgetRef ref,
) {
  ref.read(interactiveImageProvider.notifier).handleMarkerDragEnd(
        position,
        isSelected,
        ref,
      );

  updateEditorControllersPosition(host, position);
}
