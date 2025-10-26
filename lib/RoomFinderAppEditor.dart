import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:test_project/RoomFinderModels.dart';
import 'package:test_project/RoomFinderWidgets.dart';

class BuildingSettings {
  final String buildingName;
  final int floorCount;
  final String imageNamePattern;

  BuildingSettings({
    required this.buildingName,
    required this.floorCount,
    required this.imageNamePattern,
  });
}

class SettingsDialog extends StatefulWidget {
  final String initialBuildingName;
  final int initialFloorCount;
  final String initialImagePattern;

  const SettingsDialog({
    super.key,
    required this.initialBuildingName,
    required this.initialFloorCount,
    required this.initialImagePattern,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _floorCountController;
  late final TextEditingController _imagePatternController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialBuildingName);
    _floorCountController = TextEditingController(
      text: widget.initialFloorCount.toString(),
    );
    _imagePatternController = TextEditingController(
      text: widget.initialImagePattern,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _floorCountController.dispose();
    _imagePatternController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    if (_formKey.currentState!.validate()) {
      final settings = BuildingSettings(
        buildingName: _nameController.text.trim(),
        floorCount: int.parse(_floorCountController.text),
        imageNamePattern: _imagePatternController.text.trim(),
      );
      Navigator.pop(context, settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('建物設定'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '建物名',
                  hintText: '例: 全学講義棟1号館',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '建物名を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _floorCountController,
                decoration: const InputDecoration(labelText: '階層数'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '階層数を入力してください';
                  }
                  final int? count = int.tryParse(value);
                  if (count == null || count <= 0) {
                    return '1以上の数値を入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _imagePatternController,
                decoration: const InputDecoration(
                  labelText: '画像ファイルの識別名',
                  helperText:
                      '例: "my_building"\n→ "my_building_1f.png", "my_building_2f.png"...',
                  helperMaxLines: 3,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '識別名を入力してください';
                  }
                  if (value.contains(RegExp(r'[\s_]'))) {
                    return 'スペースやアンダースコア(_)は含めないでください';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('キャンセル'),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        ElevatedButton(child: const Text('保存'), onPressed: _saveSettings),
      ],
    );
  }
}

abstract class EditorControllerHost {
  TextEditingController get nameController;
  TextEditingController get xController;
  TextEditingController get yController;
}

class EditorView extends CustomView {
  const EditorView({super.key}) : super(mode: CustomViewMode.editor);

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView>
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

  void _prepareEditorDraft(BDataContainer container) {
    container.ensureDraftReadyForEditor();
  }

  @override
  void initState() {
    super.initState();
    final bDataContainer = context.read<BDataContainer>();
    _prepareEditorDraft(bDataContainer);
    pageController = PageController(
      initialPage: bDataContainer.floorCount - currentFloor,
    );
    activeBuildingId = bDataContainer.activeBuildingId;

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

    final bDataContainer = context.read<BDataContainer>();
    final updatedData = selectedElement!.copyWith(name: trimmedName);
    bDataContainer.updateSData(updatedData);
    setState(() => selectedElement = updatedData);
  }

  void _updateTapPositionFromTextFields() {
    if (isDragging || selectedElement == null) return;

    final double? x = double.tryParse(_xController.text);
    final double? y = double.tryParse(_yController.text);
    if (x == null || y == null) return;

    final newPosition = Offset(x, y);
    if (selectedElement!.position == newPosition) return;

    final bDataContainer = context.read<BDataContainer>();
    final updatedData = selectedElement!.copyWith(position: newPosition);
    bDataContainer.updateSData(updatedData);
    setState(() {
      tapPosition = newPosition;
      selectedElement = updatedData;
    });
  }

  Widget _buildTypeSelector() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: PlaceType.values.map((type) {
        final isSelected = currentType == type;
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? type.color : null,
            foregroundColor: isSelected ? Colors.white : null,
          ),
          onPressed: () => setState(() => currentType = type),
          child: Text(type.label),
        );
      }).toList(),
    );
  }

  @override
  void onTapDetected(Offset position) {
    if (isConnecting) {
      final tappedElement = _findElementAtPosition(
        position,
        context.read<BDataContainer>(),
        currentFloor,
      );

      bool canConnect = false;
      final start = connectingStart;
      if (tappedElement == null ||
          start == null ||
          tappedElement.id == start.id) {
        canConnect = false;
      } else {
        final sameFloor = tappedElement.floor == start.floor;
        final startType = start.type;
        final tappedType = tappedElement.type;

        if (!sameFloor) {
          canConnect =
              (startType == PlaceType.elevator &&
              tappedType == PlaceType.elevator);
        } else {
          final bool tappedIsConnectable = tappedType.isGraphNode;

          final bool startIsSpecial =
              (startType == PlaceType.elevator ||
              startType == PlaceType.entrance);
          final bool tappedIsSpecial =
              (tappedType == PlaceType.elevator ||
              tappedType == PlaceType.entrance);

          final bool isProhibitedConnection = startIsSpecial && tappedIsSpecial;

          canConnect = tappedIsConnectable && !isProhibitedConnection;
        }
      }

      if (canConnect) {
        final bDataContainer = context.read<BDataContainer>();
        bDataContainer.addEdge(connectingStart!.id, tappedElement!.id);
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

  CachedSData? _findElementAtPosition(
    Offset position,
    BDataContainer bDataContainer,
    int floor,
  ) {
    final relevantElements = bDataContainer.cachedSDataList
        .where((sData) => sData.floor == floor)
        .toList();
    for (final element in relevantElements) {
      final distance = (position - element.position).distance;
      if (distance <= 12.0) {
        return element;
      }
    }
    return null;
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
    final bDataContainer = context.read<BDataContainer>();

    final BuildingSettings? newSettings = await showDialog<BuildingSettings>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return SettingsDialog(
          initialBuildingName: bDataContainer.buildingName,
          initialFloorCount: bDataContainer.floorCount,
          initialImagePattern: bDataContainer.imageNamePattern,
        );
      },
    );

    if (newSettings != null && mounted) {
      bDataContainer.updateBuildingSettings(
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
    context.read<BDataContainer>().rebuildRoomPassageEdges();
  }

  @override
  Widget build(BuildContext context) {
    final bDataContainer = context.read<BDataContainer>();
    final displaySText = bDataContainer.buildSnapshot();

    return Container(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '$currentFloor階',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const VerticalDivider(thickness: 1, indent: 8, endIndent: 8),
                Expanded(child: _buildTypeSelector()),
              ],
            ),
          ),

          buildInteractiveImage(),

          const SizedBox(height: 4),

          if (tapPosition != null || isConnecting)
            SizedBox(
              height: 78,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    if (!isConnecting) ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: '名前',
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _xController,
                              decoration: const InputDecoration(
                                labelText: 'X',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _yController,
                              decoration: const InputDecoration(
                                labelText: 'Y',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      Text(
                        '接続モード: 接続先のノードをタップ',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          if (selectedElement == null && !isConnecting)
                            Expanded(
                              child: ElevatedButton(
                                child: const Text('追加する!'),
                                onPressed: () {
                                  final bDataContainer = context
                                      .read<BDataContainer>();

                                  final String name = _nameController.text
                                      .trim();
                                  final double? x = double.tryParse(
                                    _xController.text,
                                  );
                                  final double? y = double.tryParse(
                                    _yController.text,
                                  );

                                  if (name.isEmpty || x == null || y == null) {
                                    print("入力エラー: 名前、X、Yを正しく入力してください。");
                                    return;
                                  }

                                  CachedSData newSData = CachedSData(
                                    id: const Uuid().v4(),
                                    name: name,
                                    position: Offset(x, y),
                                    floor: currentFloor,
                                    type: currentType,
                                  );
                                  bDataContainer.addSData(newSData);
                                  setState(() {
                                    tapPosition = null;
                                    selectedElement = null;
                                    _nameController.clear();
                                    _xController.clear();
                                    _yController.clear();
                                  });
                                },
                              ),
                            ),
                          if (selectedElement != null) ...[
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text(
                                  '削除する!',
                                  style: TextStyle(color: Colors.white),
                                ),
                                onPressed: () async {
                                  final bDataContainer = context
                                      .read<BDataContainer>();
                                  final elementToDelete = selectedElement!;

                                  bool shouldDelete = true;

                                  if (elementToDelete.type.isGraphNode &&
                                      bDataContainer.hasEdges(
                                        elementToDelete.id,
                                      )) {
                                    if (!mounted) return;

                                    final bool?
                                    confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (BuildContext dialogContext) {
                                        return AlertDialog(
                                          title: const Text('削除の確認'),
                                          content: const Text(
                                            'この要素には接続されたエッジがあります。本当に削除しますか？\n関連するエッジもすべて削除されます。',
                                          ),
                                          actions: <Widget>[
                                            TextButton(
                                              child: const Text('キャンセル'),
                                              onPressed: () {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop(false);
                                              },
                                            ),
                                            TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.red,
                                              ),
                                              child: const Text('削除する!'),
                                              onPressed: () {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop(true);
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (confirmed != true) {
                                      shouldDelete = false;
                                    }
                                  }

                                  if (shouldDelete) {
                                    if (!mounted) return;

                                    bDataContainer.removeSData(elementToDelete);
                                    setState(() {
                                      selectedElement = null;
                                      tapPosition = null;
                                      _nameController.clear();
                                      _xController.clear();
                                      _yController.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                            if (selectedElement!.type.isGraphNode) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  child: const Text('接続する!'),
                                  onPressed: _toggleConnectionMode,
                                ),
                              ),
                            ],
                          ],
                          if (isConnecting)
                            Expanded(
                              child: ElevatedButton(
                                child: const Text('接続しない!'),
                                onPressed: _toggleConnectionMode,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 78,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '画像をタップして座標を取得\n上下スワイプで階層移動',
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _rebuildRoomPassageEdges,
                        child: const Text('部屋と廊下を接続'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Container(height: 2, color: Colors.grey[300]),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth - 16,
                height: 120,
                child: Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          displaySText,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.settings),
                            onPressed: _openSettingsDialog,
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'コピー',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: displaySText),
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('コピーしました')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
