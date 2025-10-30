import 'package:flutter/material.dart';
import 'package:test_project/models/room_finder_models.dart';

class FinderDetailContent extends StatelessWidget {
  const FinderDetailContent({
    super.key,
    required this.currentFloor,
    required this.dropdownValue,
    required this.roomsInBuilding,
    required this.selectedRoomInfo,
    required this.onRoomSelected,
    required this.onReturnToSearch,
    required this.interactiveImage,
    required this.selectedElementLabel,
    required this.onStartNavigation,
  });

  final int currentFloor;
  final String? dropdownValue;
  final List<BuildingRoomInfo> roomsInBuilding;
  final BuildingRoomInfo? selectedRoomInfo;
  final ValueChanged<String?> onRoomSelected;
  final VoidCallback onReturnToSearch;
  final Widget interactiveImage;
  final String selectedElementLabel;
  final VoidCallback? onStartNavigation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '$currentFloor階',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const VerticalDivider(thickness: 1, indent: 8, endIndent: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dropdownValue,
                      isExpanded: true,
                      hint: const Text('部屋を選択', style: TextStyle(fontSize: 13)),
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      items: roomsInBuilding.map((info) {
                        final title = info.room.name.isEmpty ? info.room.id : info.room.name;
                        return DropdownMenuItem<String>(
                          value: info.room.id,
                          child: Text(title, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: onRoomSelected,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onReturnToSearch,
                  child: const Text('検索へ戻る', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
        interactiveImage,
        const SizedBox(height: 4),
        Container(height: 2, color: Colors.grey.shade300),
        const SizedBox(height: 4),
        SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedRoomInfo != null
                            ? '建物: ${selectedRoomInfo!.buildingName}'
                            : '建物: -',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          selectedElementLabel,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                selectedRoomInfo == null
                    ? const SizedBox.shrink()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: onStartNavigation,
                        child: const Text(
                          'ルートを検索する!',
                          style: TextStyle(fontSize: 14, color: Colors.white),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
