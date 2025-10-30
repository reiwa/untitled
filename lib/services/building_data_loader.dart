import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test_project/models/room_finder_models.dart';

const String kBuildingDataAssetPath = 'assets/data/buildings.json';

Future<void> loadBuildingData(
  WidgetRef ref, {
  String assetPath = kBuildingDataAssetPath,
}) async {
  final raw = await rootBundle.loadString(assetPath);
  ref.read(buildingRepositoryProvider.notifier).loadBuildingsFromJson(raw);
}
