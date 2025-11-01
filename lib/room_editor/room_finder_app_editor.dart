import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/element_data_models.dart';
import 'package:test_project/viewer/interactive_image_state.dart';
import 'package:test_project/models/room_finder_models.dart';
import 'package:test_project/viewer/room_finder_viewer.dart';

import 'building_settings_dialog.dart';
import 'editor_fixed_screen.dart';
import 'editor_action_screen.dart';
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

  void _prepareEditorDraft() {
    ref.read(activeBuildingProvider.notifier).startDraftFromActive();
  }

  @override
  void initState() {
    super.initState();

    final snap = ref.read(activeBuildingProvider);
    final imageState = ref.read(interactiveImageProvider);
    pageController = PageController(
      initialPage: snap.floorCount - imageState.currentFloor,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prepareEditorDraft();
      }

      final snap = ref.read(activeBuildingProvider);
      final notifier = ref.read(interactiveImageProvider.notifier);

      notifier.handleBuildingChanged(snap.id);

      ref.read(activeRouteProvider.notifier).clearActiveRouteNodes();

      _xController.addListener(_updateTapPositionFromTextFields);
      _yController.addListener(_updateTapPositionFromTextFields);
      _nameController.addListener(_updateNameFromTextField);

      isPageScrollable = canSwipeFloors;

      ref.listenManual<InteractiveImageState>(interactiveImageProvider, (prev, next) {
        if (!mounted) return;
        if (prev?.selectedElement?.id != next.selectedElement?.id) {
          final sel = next.selectedElement;
          if (sel == null) {
            _nameController.clear();
            _xController.clear();
            _yController.clear();
          } else {
            _nameController.text = sel.name;
            _xController.text = sel.position.dx.toStringAsFixed(0);
            _yController.text = sel.position.dy.toStringAsFixed(0);
          }
        }
        if (next.selectedElement == null &&
            prev?.tapPosition != next.tapPosition) {
          final p = next.tapPosition;
          if (p == null) {
            _nameController.clear();
            _xController.clear();
            _yController.clear();
          } else {
            _nameController.text = '新しい要素';
            _xController.text = p.dx.toStringAsFixed(0);
            _yController.text = p.dy.toStringAsFixed(0);
          }
        }

        if (prev?.currentFloor != next.currentFloor) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            ref
                .read(interactiveImageProvider.notifier)
                .applyPendingFocusIfAny();

            if (next.pendingFocusElement != null) {
              ref.read(interactiveImageProvider.notifier).updateCurrentZoomScale();
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _xController.removeListener(_updateTapPositionFromTextFields);
    _yController.removeListener(_updateTapPositionFromTextFields);
    _nameController.removeListener(_updateNameFromTextField);

    _nameController.dispose();
    _xController.dispose();
    _yController.dispose();

    super.dispose();
  }

  void _updateNameFromTextField() {
    ref
        .read(interactiveImageProvider.notifier)
        .updateElementName(_nameController.text, ref);
  }

  void _updateTapPositionFromTextFields() {
    final double? x = double.tryParse(_xController.text);
    final double? y = double.tryParse(_yController.text);
    if (x == null || y == null) return;
    ref
        .read(interactiveImageProvider.notifier)
        .updateElementPosition(Offset(x, y), ref);
  }

  void _toggleConnectionMode() {
    ref.read(interactiveImageProvider.notifier).toggleConnectionMode();
  }

  void _openSettingsDialog() async {
    final active = ref.read(activeBuildingProvider);
    final imageState = ref.watch(interactiveImageProvider);

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
      ref
          .read(activeBuildingProvider.notifier)
          .updateBuildingSettings(
            name: newSettings.buildingName,
            floors: newSettings.floorCount,
            pattern: newSettings.imageNamePattern,
          );

      if (imageState.currentFloor > newSettings.floorCount) {
        pageController.jumpToPage(newSettings.floorCount - 1);
      }
    }
  }

  void _rebuildRoomPassageEdges() {
    ref.read(activeBuildingProvider.notifier).rebuildRoomPassageEdges();
  }

  void _handleAddPressed() {
    final name = _nameController.text.trim();
    final double? x = double.tryParse(_xController.text);
    final double? y = double.tryParse(_yController.text);

    if (name.isEmpty || x == null || y == null) {
      debugPrint("入力エラー: 名前、X、Yを正しく入力してください。");
      return;
    }

    ref
        .read(interactiveImageProvider.notifier)
        .addElement(name: name, position: Offset(x, y), ref: ref);
  }

  Future<void> _handleDeletePressed() async {
    final elementToDelete = ref.read(interactiveImageProvider).selectedElement;
    if (elementToDelete == null) return;

    bool shouldDelete = true;

    if (elementToDelete.type.isGraphNode &&
        ref
            .read(activeBuildingProvider.notifier)
            .hasEdges(elementToDelete.id)) {
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

    ref.read(interactiveImageProvider.notifier).deleteSelectedElement(ref);
  }

  @override
  Widget build(BuildContext context) {
    final imageState = ref.watch(interactiveImageProvider);
    ref.watch(activeBuildingProvider);
    final displaySText = ref
        .read(activeBuildingProvider.notifier)
        .buildSnapshot();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _FloorHeader(
          currentFloor: imageState.currentFloor,
          currentType: imageState.currentType,
          onTypeSelected: (type) =>
              ref.read(interactiveImageProvider.notifier).setCurrentType(type),
        ),
        buildInteractiveImage(),
        const SizedBox(height: 4),
        if (imageState.tapPosition != null || imageState.isConnecting)
          EditorActionScreen(
            isConnecting: imageState.isConnecting,
            selectedElement: imageState.selectedElement,
            nameController: _nameController,
            xController: _xController,
            yController: _yController,
            onAdd: _handleAddPressed,
            onDelete: _handleDeletePressed,
            onToggleConnect: _toggleConnectionMode,
          )
        else
          EditorIdleScreen(onRebuildPressed: _rebuildRoomPassageEdges),
        const SizedBox(height: 4),
        Container(height: 2, color: Colors.grey[300]),
        const SizedBox(height: 4),
        SnapshotScreen(
          displaySText: displaySText,
          onSettingsPressed: _openSettingsDialog,
          onCopyPressed: () async {
            await Clipboard.setData(ClipboardData(text: displaySText));
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('コピーしました')));
            }
          },
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
