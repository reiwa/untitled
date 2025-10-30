import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:uuid/uuid.dart';
import 'package:test_project/models/room_finder_models.dart';
import 'package:test_project/viewer/room_finder_viewer.dart';

import 'building_settings_dialog.dart';
import 'editor_fixed_screen.dart';
import 'editor_action_screen.dart';
import 'editor_connection_handler.dart';
import 'snapshot_screen.dart';

abstract class EditorControllerHost {
  TextEditingController get nameController;
  TextEditingController get xController;
  TextEditingController get yController;
}

class EditorView extends CustomView {
  const EditorView({super.key}) : super(mode: CustomViewMode.editor);

  @override
  ConsumerState<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends ConsumerState<EditorView>
    with InteractiveImageMixin<EditorView>
    implements EditorControllerHost {
  final _nameController = TextEditingController();
  final _xController = TextEditingController();
  final _yController = TextEditingController();

  @override
  TextEditingController get nameController => _nameController;

  @override
  TextEditingController get xController => _xController;

  @override
  TextEditingController get yController => _yController;

  void _updatePhysicsOnZoomChange() {
    final bool canSwipeNow = canSwipeFloors;

    if (isPageScrollable != canSwipeNow) {
      setState(() {
        isPageScrollable = canSwipeNow;
      });
    }
  }

  void _prepareEditorDraft() {
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(activeBuildingProvider.notifier).startDraftFromActive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prepareEditorDraft();
      }
    });

    final container = ProviderScope.containerOf(context, listen: false);
    final snap = container.read(activeBuildingProvider);

    pageController = PageController(
      initialPage: snap.floorCount - currentFloor,
    );
    activeBuildingId = snap.id;

    _xController.addListener(_updateTapPositionFromTextFields);
    _yController.addListener(_updateTapPositionFromTextFields);
    _nameController.addListener(_updateNameFromTextField);

    isPageScrollable = canSwipeFloors;
    transformationController.addListener(_updatePhysicsOnZoomChange);
  }

  @override
  void dispose() {
    _xController.removeListener(_updateTapPositionFromTextFields);
    _yController.removeListener(_updateTapPositionFromTextFields);
    _nameController.removeListener(_updateNameFromTextField);

    transformationController.removeListener(_updatePhysicsOnZoomChange);

    _nameController.dispose();
    _xController.dispose();
    _yController.dispose();

    super.dispose();
  }

  void _updateNameFromTextField() {
    if (isDragging || selectedElement == null) return;

    final trimmedName = _nameController.text.trim();
    if (trimmedName == selectedElement!.name) return;

    final container = ProviderScope.containerOf(context, listen: false);
    final updatedData = selectedElement!.copyWith(name: trimmedName);
    container.read(activeBuildingProvider.notifier).updateSData(updatedData);
    setState(() => selectedElement = updatedData);
  }

  void _updateTapPositionFromTextFields() {
    if (isDragging || selectedElement == null) return;

    final double? x = double.tryParse(_xController.text);
    final double? y = double.tryParse(_yController.text);
    if (x == null || y == null) return;

    final newPosition = Offset(x, y);
    if (selectedElement!.position == newPosition) return;

    final container = ProviderScope.containerOf(context, listen: false);
    final updatedData = selectedElement!.copyWith(position: newPosition);
    container.read(activeBuildingProvider.notifier).updateSData(updatedData);
    setState(() {
      tapPosition = newPosition;
      selectedElement = updatedData;
    });
  }

  @override
  void onTapDetected(Offset position) {
    final container = ProviderScope.containerOf(context, listen: false);
    final active = container.read(activeBuildingProvider);

    if (isConnecting) {
      final tappedElement = findElementAtPosition(
        position,
        active.elements.where((sData) => sData.floor == currentFloor),
      );
      final start = connectingStart;
      final bool canConnect =
          start != null && tappedElement != null && canConnectNodes(start, tappedElement);
      if (canConnect) {
        container.read(activeBuildingProvider.notifier).addEdge(start.id, tappedElement.id);
        setState(() {
          isConnecting = false;
          connectingStart = null;
          previewPosition = null;
          tapPosition = null;
        });
        _nameController.clear();
        _xController.clear();
        _yController.clear();
      }
      return;
    }

    if (selectedElement != null) {
      final distance = (position - selectedElement!.position).distance;
      if (distance > 12.0) {
        setState(() {
          selectedElement = null;
          tapPosition = position;
        });
        _nameController.text = '新しい要素';
        _xController.text = position.dx.toStringAsFixed(0);
        _yController.text = position.dy.toStringAsFixed(0);
        return;
      }
    }

    setState(() {
      if (tapPosition == position) {
        tapPosition = null;
        _nameController.clear();
        _xController.clear();
        _yController.clear();
      } else {
        tapPosition = position;
      }
    });

    if (selectedElement == null) {
      _xController.text = position.dx.toStringAsFixed(0);
      _yController.text = position.dy.toStringAsFixed(0);
      _nameController.text = '新しい要素';
    }
  }

  void _toggleConnectionMode() {
    if (isConnecting) {
      setState(() {
        isConnecting = false;
        connectingStart = null;
        previewPosition = null;
      });
    } else if (selectedElement != null && selectedElement!.type.isGraphNode) {
      setState(() {
        isConnecting = true;
        connectingStart = selectedElement;
        selectedElement = null;
        tapPosition = null;
        previewPosition = Offset.zero;
      });
      _nameController.clear();
      _xController.clear();
      _yController.clear();
    }
  }

  void _openSettingsDialog() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final active = container.read(activeBuildingProvider);

    final BuildingSettings? newSettings = await showDialog<BuildingSettings>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return SettingsDialog(
          initialBuildingName: active.name,
          initialFloorCount: active.floorCount,
          initialImagePattern: active.imagePattern,
        );
      },
    );

    if (newSettings != null && mounted) {
      container.read(activeBuildingProvider.notifier).updateBuildingSettings(
            name: newSettings.buildingName,
            floors: newSettings.floorCount,
            pattern: newSettings.imageNamePattern,
          );

      if (currentFloor > newSettings.floorCount) {
        pageController.jumpToPage(newSettings.floorCount - 1);
      } else {
        setState(() {});
      }
    }
  }

  void _rebuildRoomPassageEdges() {
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(activeBuildingProvider.notifier).rebuildRoomPassageEdges();
  }

  void _handleAddPressed() {
    final name = _nameController.text.trim();
    final double? x = double.tryParse(_xController.text);
    final double? y = double.tryParse(_yController.text);

    if (name.isEmpty || x == null || y == null) {
      print("入力エラー: 名前、X、Yを正しく入力してください。");
      return;
    }

    final newSData = CachedSData(
      id: const Uuid().v4(),
      name: name,
      position: Offset(x, y),
      floor: currentFloor,
      type: currentType,
    );
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(activeBuildingProvider.notifier).addSData(newSData);
    setState(() {
      tapPosition = null;
      selectedElement = null;
      _nameController.clear();
      _xController.clear();
      _yController.clear();
    });
  }

  Future<void> _handleDeletePressed() async {
    final elementToDelete = selectedElement;
    if (elementToDelete == null) return;

    final container = ProviderScope.containerOf(context, listen: false);
    bool shouldDelete = true;

    if (elementToDelete.type.isGraphNode &&
        container.read(activeBuildingProvider.notifier).hasEdges(elementToDelete.id)) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('削除の確認'),
            content: const Text(
              'この要素には接続されたエッジがあります。本当に削除しますか？\n関連するエッジもすべて削除されます。',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('キャンセル'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('削除する!'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        shouldDelete = false;
      }
    }

    if (!shouldDelete || !mounted) return;

    container.read(activeBuildingProvider.notifier).removeSData(elementToDelete);
    setState(() {
      selectedElement = null;
      tapPosition = null;
      _nameController.clear();
      _xController.clear();
      _yController.clear();
    });
  }

  Future<void> _handleCopySnapshot(String displaySText) async {
    await Clipboard.setData(ClipboardData(text: displaySText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コピーしました')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final displaySText = container.read(activeBuildingProvider.notifier).buildSnapshot();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _FloorHeader(
          currentFloor: currentFloor,
          currentType: currentType,
          onTypeSelected: (type) => setState(() => currentType = type),
        ),
        buildInteractiveImage(),
        const SizedBox(height: 4),
        if (tapPosition != null || isConnecting)
          EditorActionScreen(
            isConnecting: isConnecting,
            selectedElement: selectedElement,
            nameController: _nameController,
            xController: _xController,
            yController: _yController,
            onAdd: _handleAddPressed,
            onDelete: _handleDeletePressed,
            onToggleConnect: _toggleConnectionMode,
          )
        else
          EditorIdleScreen(
            onRebuildPressed: _rebuildRoomPassageEdges,
          ),
        const SizedBox(height: 4),
        Container(height: 2, color: Colors.grey[300]),
        const SizedBox(height: 4),
        SnapshotScreen(
          displaySText: displaySText,
          onSettingsPressed: _openSettingsDialog,
          onCopyPressed: () => _handleCopySnapshot(displaySText),
        ),
      ],
    );
  }
}

class _FloorHeader extends StatelessWidget {
  final int currentFloor;
  final PlaceType currentType;
  final ValueChanged<PlaceType> onTypeSelected;

  const _FloorHeader({
    required this.currentFloor,
    required this.currentType,
    required this.onTypeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '$currentFloor階',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const VerticalDivider(thickness: 1, indent: 8, endIndent: 8),
          Expanded(
            child: PlaceTypeSelector(
              currentType: currentType,
              onTypeSelected: onTypeSelected,
            ),
          ),
        ],
      ),
    );
  }
}
