import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    _floorCountController =
        TextEditingController(text: widget.initialFloorCount.toString());
    _imagePatternController =
        TextEditingController(text: widget.initialImagePattern);
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
                  hintText: '例: 全学講義棠1号館',
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
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(onPressed: _saveSettings, child: const Text('保存')),
      ],
    );
  }
}