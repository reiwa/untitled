import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:test_project/RoomFinderAppShared.dart';

class FinderView extends CustomView {
  const FinderView({super.key});

  @override
  State<FinderView> createState() => _FinderViewState();
}

class _FinderViewState extends State<FinderView>
    with InteractiveImageMixin<FinderView> {
  
  Offset? _tapPosition;
  PlaceType currentType = PlaceType.room;

  final TransformationController _transformationController =
      TransformationController();

  @override
  void onTapDetected(Offset position) {

  }

  @override
  Widget build(BuildContext context) {
    final bDataContainer = context.watch<BDataContainer>();
    return Container(
      child: Column(
        children: <Widget>[
          buildInteractiveImage(),
      ],)
    );
  }
}
