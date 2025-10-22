import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:test_project/RoomFinderAppShared.dart';

abstract class EditorControllerHost {
  TextEditingController get nameController;
  TextEditingController get xController;
  TextEditingController get yController;
}

class EditorView extends CustomView {
  const EditorView({super.key});

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView>
    with InteractiveImageMixin<EditorView>
    implements EditorControllerHost {
  @override
  bool get showTapDot => true;

  PlaceType currentType = PlaceType.room;

  final TransformationController _transformationController =
      TransformationController();

  final _nameController = TextEditingController();
  final _xController = TextEditingController();
  final _yController = TextEditingController();
  var test = _EditorViewState;

  @override
  TextEditingController get nameController => _nameController;

  @override
  TextEditingController get xController => _xController;

  @override
  TextEditingController get yController => _yController;

  @override
  void initState() {
    super.initState();
    _xController.addListener(_updateTapPositionFromTextFields);
    _yController.addListener(_updateTapPositionFromTextFields);
    _nameController.addListener(_updateNameFromTextField);
  }

  @override
  void dispose() {
    _xController.removeListener(_updateTapPositionFromTextFields);
    _yController.removeListener(_updateTapPositionFromTextFields);
    _nameController.removeListener(_updateNameFromTextField);

    _nameController.dispose();
    _xController.dispose();
    _yController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _updateNameFromTextField() {
    if (isDragging) return;

    if (selectedElement != null) {
      final bDataContainer = context.read<BDataContainer>();
      final updatedData = CachedSData(
        id: selectedElement!.id,
        name: _nameController.text,
        position: selectedElement!.position,
        floor: selectedElement!.floor,
        type: selectedElement!.type,
      );
      bDataContainer.updateSData(updatedData);
      setState(() {
        selectedElement = updatedData;
      });
    }
  }

  void _updateTapPositionFromTextFields() {
    if (isDragging) return;

    final double? x = double.tryParse(_xController.text);
    final double? y = double.tryParse(_yController.text);

    if (x != null && y != null && selectedElement != null) {
      final newPosition = Offset(x, y);
      final bDataContainer = context.read<BDataContainer>();
      final updatedData = CachedSData(
        id: selectedElement!.id,
        name: selectedElement!.name,
        position: newPosition,
        floor: selectedElement!.floor,
        type: selectedElement!.type,
      );
      bDataContainer.updateSData(updatedData);
      setState(() {
        tapPosition = newPosition;
        selectedElement = updatedData;
      });
    }
  }

  @override
  void onTapDetected(Offset position) {
    if (isConnecting) {
      final tappedElement = _findElementAtPosition(
        position,
        context.read<BDataContainer>(),
      );
      if (tappedElement != null &&
          (tappedElement.type == PlaceType.passage || 
              tappedElement.type == PlaceType.elevator) &&
          tappedElement.id != connectingStart?.id) {
        final bDataContainer = context.read<BDataContainer>();
        bDataContainer.addEdge(connectingStart!.id, tappedElement.id);
        setState(() {
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
      tapPosition = position;
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
  ) {
    final relevantElements = bDataContainer.cachedSDataList
        .where((sData) => sData.floor == 1)
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
    } else if (selectedElement?.type == PlaceType.passage ||
        selectedElement!.type == PlaceType.elevator) {
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

  @override
  Widget build(BuildContext context) {
    final bDataContainer = context.read<BDataContainer>();
    String displaySText = '';
    displaySText +=
        '{\n'
        ' "building_name": "${bDataContainer.buildingName}"\n'
        ' "floors": [1, 2, 3],\n'
        ' "elements": [\n';
    for (int i = 0; i < bDataContainer.cachedSDataList.length; i++) {
      displaySText +=
          '   {\n'
          '     "id": "${bDataContainer.cachedSDataList[i].id}",\n'
          '     "name": "${bDataContainer.cachedSDataList[i].name}",\n'
          '     "position": { "x": ${bDataContainer.cachedSDataList[i].position.dx.round()}, "y": ${bDataContainer.cachedSDataList[i].position.dy.round()} },\n'
          '     "floor": ${bDataContainer.cachedSDataList[i].floor},\n'
          '     "type": "${bDataContainer.cachedSDataList[i].type.name}"\n';
      displaySText += i == bDataContainer.cachedSDataList.length - 1
          ? '   }\n'
          : '   },\n';
    }
    displaySText +=
        ' ],\n'
        ' "edges": [\n';
    final allEdges = bDataContainer.cachedPDataList
        .expand((pData) => pData.edges)
        .toList();
    for (int i = 0; i < allEdges.length; i++) {
      final edgeSet = allEdges[i];
      if (edgeSet.length == 2) {
        final ids = edgeSet.toList();
        displaySText += '   ["${ids[0]}", "${ids[1]}"]';
        displaySText += i == allEdges.length - 1 ? '\n' : ',\n';
      }
    }
    displaySText +=
        ' ]\n'
        '}';

    return Container(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentType == PlaceType.room
                        ? typeColors[PlaceType.room]
                        : null,
                    foregroundColor: currentType == PlaceType.room
                        ? Colors
                              .white
                        : null,
                  ),
                  child: const Text('部屋'),
                  onPressed: () {
                    setState(() {
                      currentType = PlaceType.room;
                    });
                  },
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentType == PlaceType.passage
                        ? typeColors[PlaceType.passage]
                        : null,
                    foregroundColor: currentType == PlaceType.passage
                        ? Colors.white
                        : null,
                  ),
                  child: const Text('廊下'),
                  onPressed: () {
                    setState(() {
                      currentType = PlaceType.passage;
                    });
                  },
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentType == PlaceType.elevator
                        ? typeColors[PlaceType.elevator]
                        : null,
                    foregroundColor: currentType == PlaceType.elevator
                        ? Colors.white
                        : null,
                  ),
                  child: const Text('階段など'),
                  onPressed: () {
                    setState(() {
                      currentType = PlaceType.elevator;
                    });
                  },
                ),
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
                      const Text(
                        '接続モード: 別の廊下をタップして接続',
                        style: TextStyle(
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

                                  final String name = _nameController.text;
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
                                    floor: 1,
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
                                  final elementToDelete =
                                      selectedElement!;

                                  bool shouldDelete = true;

                                  if ((elementToDelete.type == PlaceType.passage ||
                                          elementToDelete.type == PlaceType.elevator) &&
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
                            if (selectedElement!.type == PlaceType.passage ||
                                selectedElement!.type == PlaceType.elevator) ...[
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
              child: const Text(
                '画像をタップして座標を取得',
                style: TextStyle(fontSize: 10),
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
                child: SingleChildScrollView(
                  child: SelectableText(
                    displaySText,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
