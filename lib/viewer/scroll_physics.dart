import 'dart:math';
import 'package:flutter/material.dart';

class TolerantPageScrollPhysics extends PageScrollPhysics {
  final bool Function() canScroll;
  final double directionTolerance;

  const TolerantPageScrollPhysics({
    required this.canScroll,
    this.directionTolerance = pi / 6,
    ScrollPhysics? parent,
  }) : super(parent: parent);

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      canScroll() && super.shouldAcceptUserOffset(position);

  @override
  TolerantPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return TolerantPageScrollPhysics(
      canScroll: canScroll,
      directionTolerance: directionTolerance,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!canScroll()) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset * 0.9);
  }

  @override
  bool get allowImplicitScrolling =>
      canScroll() && super.allowImplicitScrolling;
}