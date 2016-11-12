// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'box.dart';
import 'object.dart';

enum WrapDirection {
  rightThenDown,
  rightThenUp,
  leftThenDown,
  leftThenUp,
  downThenRight,
  downThenLeft,
  upThenRight,
  upThenLeft,
}

enum _WrapAlignment {
  start,
  center,
  end,
}

class WrapAlignment {
  const WrapAlignment._(this._alignment, [ this._justified = false ]);

  static const WrapAlignment start = const WrapAlignment._(_WrapAlignment.start);
  static const WrapAlignment center = const WrapAlignment._(_WrapAlignment.center);
  static const WrapAlignment end = const WrapAlignment._(_WrapAlignment.end);

  factory WrapAlignment.justified({ @required WrapAlignment fallback }) {
    assert(fallback != null);
    assert(!fallback._justified);
    return new WrapAlignment._(fallback._alignment, true);
  }

  final _WrapAlignment _alignment;
  final bool _justified;
}

enum WrapCrossAlignment {
  start,
  center,
  end,
  // TODO(ianh): baseline
}

class WrapParentData extends ContainerBoxParentDataMixin<RenderBox> {
  int _run;
}

/*

layout stores the total cross extent of the runs, crossAxisRunExtents

tertiary alignment is just done at paint time
 - start is trivial
 - center adds half crossAxisExtent-crossAxisRunExtents to the offset then is trivial
 - end adds crossAxisExtent-crossAxisRunExtents to the offset then is trivial
 - justify adds child.parentData._run * (crossAxisExtent-crossAxisRunExtents) / (lastChild.parentData._run + 1) to each offset

secondary treats "justify" as "center"
*/

// TODO(ianh): Support "minimum width and fill row" for last item

class RenderWrap extends RenderBox with ContainerRenderObjectMixin<RenderBox, WrapParentData>,
                                        RenderBoxContainerDefaultsMixin<RenderBox, WrapParentData> {
  RenderWrap({
    List<RenderBox> children,
    WrapDirection direction: WrapDirection.rightThenDown,
    WrapAlignment primaryAlignment: WrapAlignment.start,
    double primarySpacing: 0.0,
    WrapCrossAlignment secondaryAlignment: WrapCrossAlignment.start,
    WrapAlignment tertiaryAlignment: WrapAlignment.start,
    double tertiarySpacing: 0.0,
  }) : _direction = direction,
       _primaryAlignment = primaryAlignment,
       _primarySpacing = primarySpacing,
       _secondaryAlignment = secondaryAlignment,
       _tertiaryAlignment = tertiaryAlignment,
       _tertiarySpacing = tertiarySpacing {
    assert(direction != null);
    assert(primaryAlignment != null);
    assert(primaryAlignment._alignment != null);
    assert(primarySpacing != null);
    assert(secondaryAlignment != null);
    assert(tertiaryAlignment != null);
    assert(tertiaryAlignment._alignment != null);
    assert(tertiarySpacing != null);
    addAll(children);
  }

  /// The direction to use as the main axis.
  WrapDirection get direction => _direction;
  WrapDirection _direction;
  set direction (WrapDirection value) {
    assert(value != null);
    if (_direction != value) {
      _direction = value;
      markNeedsLayout();
    }
  }

  Axis get primaryAxis {
    assert(direction != null);
    switch (direction) {
      case WrapDirection.rightThenDown:
      case WrapDirection.rightThenUp:
      case WrapDirection.leftThenDown:
      case WrapDirection.leftThenUp:
        return Axis.horizontal;
      case WrapDirection.downThenRight:
      case WrapDirection.downThenLeft:
      case WrapDirection.upThenRight:
      case WrapDirection.upThenLeft:
        return Axis.vertical;
    }
    return null;
  }

  /// How the children should be placed next to each other in their runs.
  ///
  /// This decides where the first child is placed relative to the second,
  /// assuming they end up on the same run.
  ///
  /// For example, if this is set to [WrapAlignment.start], and the [direction]
  /// is [WrapDirection.rightThenDown], then the first item in each row will be
  /// on the far left, then the second will be to its right, and so forth.
  ///
  /// To control the alignment within a run, see [secondaryAlignment].
  ///
  /// To control the placement of the runs themselves, see [tertiaryAlignment].
  WrapAlignment get primaryAlignment => _primaryAlignment;
  WrapAlignment _primaryAlignment;
  set primaryAlignment (WrapAlignment value) {
    assert(value != null);
    if (_primaryAlignment != value) {
      _primaryAlignment = value;
      markNeedsLayout();
    }
  }

  /// How much space to place between children in a run.
  double get primarySpacing => _primarySpacing;
  double _primarySpacing;
  set primarySpacing (double value) {
    assert(value != null);
    if (_primarySpacing != value) {
      _primarySpacing = value;
      markNeedsLayout();
    }
  }

  /// How the children within a run should be aligned relative to each other in
  /// their runs.
  ///
  /// For example, if this is set to [WrapCrossAlignment.start], and the
  /// [direction] is [WrapDirection.rightThenDown], then the tops of the
  /// children in each run will be aligned with each other.
  ///
  /// To control the placement of the children next to each other within a run,
  /// see [primaryAlignment].
  ///
  /// To control the placement of the runs themselves, see [tertiaryAlignment].
  WrapCrossAlignment get secondaryAlignment => _secondaryAlignment;
  WrapCrossAlignment _secondaryAlignment;
  set secondaryAlignment (WrapCrossAlignment value) {
    assert(value != null);
    if (_secondaryAlignment != value) {
      _secondaryAlignment = value;
      markNeedsLayout();
    }
  }

  /// How the runs should be placed in the render object.
  ///
  /// This decides where the first run is placed relative to the second.
  ///
  /// For example, if this is set to [WrapAlignment.start], and the [direction]
  /// is [WrapDirection.rightThenDown], then the first run will be at the top of
  /// the render object, then the second will be below it, and so forth.
  ///
  /// To control the placement of the children next to each other within a run,
  /// see [primaryAlignment].
  ///
  /// To control the alignment within a run, see [secondaryAlignment].
  WrapAlignment get tertiaryAlignment => _tertiaryAlignment;
  WrapAlignment _tertiaryAlignment;
  set tertiaryAlignment (WrapAlignment value) {
    assert(value != null);
    if (_tertiaryAlignment != value) {
      _tertiaryAlignment = value;
      markNeedsLayout();
    }
  }

  /// How much space to place between runs.
  double get tertiarySpacing => _tertiarySpacing;
  double _tertiarySpacing;
  set tertiarySpacing (double value) {
    assert(value != null);
    if (_tertiarySpacing != value) {
      _tertiarySpacing = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! WrapParentData)
      child.parentData = new WrapParentData();
  }

  // Do not change the child list while using one of these...
  Iterable<RenderBox> get _childIterator sync* {
    RenderBox child = firstChild;
    while (child != null) {
      yield child;
      child = childAfter(child);
    }
  }

  double _computeIntrinsicHeightForWidth(double maxWidth) {
    assert(primaryAxis == Axis.horizontal);
    double result = 0.0;
    double rowHeight = 0.0;
    double rowWidth = 0.0;
    bool hadRow = false;
    RenderBox child = firstChild;
    while (child != null) {
      double width = child.getMaxIntrinsicWidth(double.INFINITY);
      double height = child.getMaxIntrinsicHeight(width);
      rowWidth += width;
      if (rowWidth > maxWidth) {
        if (hadRow)
          result += tertiarySpacing;
        result += rowHeight;
        // This child is now the first on the next row:
        rowHeight = height;
        rowWidth = width;
        hadRow = true;
      } else {
        rowHeight = math.max(rowHeight, height);
      }
      child = childAfter(child);
    }
    if (hadRow)
      result += tertiarySpacing;
    result += rowHeight;
    return result;
  }

  double _computeIntrinsicWidthForHeight(double maxHeight) {
    assert(primaryAxis == Axis.vertical);
    double result = 0.0;
    double columnWidth = 0.0;
    double columnHeight = 0.0;
    bool hadRow = false;
    RenderBox child = firstChild;
    while (child != null) {
      double height = child.getMaxIntrinsicHeight(double.INFINITY);
      double width = child.getMaxIntrinsicWidth(height);
      columnHeight += height;
      if (columnHeight > maxHeight) {
        if (hadColumn)
          result += tertiarySpacing;
        result += columnWidth;
        // This child is now the first on the next column:
        columnWidth = width;
        columnHeight = height;
        hadRow = true;
      } else {
        columnWidth = math.max(columnWidth, width);
      }
      child = childAfter(child);
    }
    if (hadRow)
      result += tertiarySpacing;
    result += columnWidth;
    return result;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    switch (primaryAxis) {
      case Axis.horizontal:
        return _childIterator
                 .map<double>((RenderBox child) => child.getMinIntrinsicWidth(double.INFINITY))
                 .reduce((double value, double element) => math.max(value, element));
      case Axis.vertical:
        return _computeIntrinsicWidthForHeight(height);
    }
    return null;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    switch (primaryAxis) {
      case Axis.horizontal:
        return _childIterator
                 .map<double>((RenderBox child) => child.getMaxIntrinsicWidth(double.INFINITY))
                 .reduce((double value, double element) => value + element);
      case Axis.vertical:
        return _computeIntrinsicWidthForHeight(height);
    }
    return null;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    switch (primaryAxis) {
      case Axis.horizontal:
        return _computeIntrinsicHeightForWidth(width);
      case Axis.vertical:
        return _childIterator
                 .map<double>((RenderBox child) => child.getMinIntrinsicHeight(double.INFINITY))
                 .reduce((double value, double element) => math.max(value, element));
    }
    return null;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    switch (primaryAxis) {
      case Axis.horizontal:
        return _computeIntrinsicHeightForWidth(width);
      case Axis.vertical:
        return _childIterator
                 .map<double>((RenderBox child) => child.getMaxIntrinsicHeight(double.INFINITY))
                 .reduce((double value, double element) => value + element);
    }
    return null;
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
  }

  double _getCrossSize(RenderBox child) {
    switch (primaryAxis) {
      case Axis.horizontal:
        return child.size.height;
      case Axis.vertical:
        return child.size.width;
    }
    return null;
  }

  double _getMainSize(RenderBox child) {
    switch (primaryAxis) {
      case Axis.horizontal:
        return child.size.width;
      case Axis.vertical:
        return child.size.height;
    }
    return null;
  }

  @override
  void performLayout() {
    if (firstChild == null)
      return; // no children to lay out
    BoxConstraints childConstraints;
    double maxExtent;
    // TODO(ianh): Make the asserts below explain that there's no point putting a
    // Wrap in an unconstrained main axis (since then it's just a poor man's Flex).
    switch (primaryAxis) {
      case Axis.horizontal:
        assert(constraints.maxWidth.isFinite);
        childConstraints = new BoxConstraints(maxWidth: constraints.maxWidth);
        maxExtent = constraints.maxWidth;
        break;
      case Axis.vertical:
        assert(constraints.maxHeight.isFinite);
        childConstraints = new BoxConstraints(maxHeight: constraints.maxHeight);
        maxExtent = constraints.maxHeight;
        break;
    }
    assert(childConstraints != null);
    assert(maxExtent != null);
    RenderBox child = firstChild;
    RenderBox runFirstChild = firstChild;
    double primaryOffset = 0.0;
    double maxCrossExtent = 0.0;
    double tertiaryOffset = 0.0;
    Size maxSize = Size.zero;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      double childExtent = _getMainSize(child);
      if (primaryOffset > 0.0 && primaryOffset + childExtent > maxExtent) {
//        _alignRun(runFirstChild, child, maxExtent, maxCrossExtent);
        tertiaryOffset += maxCrossExtent + tertiarySpacing;
        maxCrossExtent = 0.0;
        primaryOffset = 0.0;
        runFirstChild = child;
      }
      switch (primaryAxis) {
        case Axis.horizontal:
          childParentData.offset = new Offset(primaryOffset, tertiaryOffset);
          break;
        case Axis.vertical:
          childParentData.offset = new Offset(tertiaryOffset, primaryOffset);
          break;
      }
      maxCrossExtent = math.max(maxCrossExtent, _getCrossSize(child));
      primaryOffset += childExtent + primarySpacing;
      child = childAfter(child);
    }
    if (runFirstChild != child) {
//      _alignRun(runFirstChild, child, maxExtent, maxCrossExtent);
      tertiaryOffset += maxCrossExtent + tertiarySpacing;
    }
//    _alignRuns(tertiaryOffset);
    size = constraints.constrain(maxSize);
  }

  // Size _fillRun(List<RenderBox> run, double extent, double maxExtent, double maxCrossExtent, Size maxSize) {
  //   double crossPosition;
  //   if (maxSize != Size.zero) {
  //     switch (primaryAxis) {
  //       case Axis.horizontal:
  //         crossPosition = maxSize.height + secondarySpacing;
  //         break;
  //       case Axis.vertical:
  //         crossPosition = maxSize.width + secondarySpacing;
  //         break;
  //     }
  //   } else {
  //     crossPosition = 0.0;
  //   }
  //   double mainOffset;
  //   switch (primaryAlignment) {
  //     case WrapAlignment.start:
  //       mainOffset = 0.0;
  //       break;
  //     case WrapAlignment.center:
  //       mainOffset = (maxExtent - extent) / 2.0;
  //       break;
  //     case WrapAlignment.end:
  //       mainOffset = (maxExtent - extent);
  //       break;
  //   }
  //   assert(mainOffset != null);
  //   for (RenderBox child in run) {
  //     double crossOffset;
  //     switch (secondaryAlignment) {
  //       case WrapAlignment.start:
  //         crossOffset = 0.0;
  //         break;
  //       case WrapAlignment.center:
  //         crossOffset = (maxCrossExtent - _getCrossSize(child)) / 2.0;
  //         break;
  //       case WrapAlignment.end:
  //         crossOffset = (maxCrossExtent - _getCrossSize(child));
  //         break;
  //     }
  //     WrapParentData childParentData = child.parentData;
  //     switch (primaryAxis) {
  //       case Axis.horizontal:
  //         childParentData.offset = new Offset(mainOffset, crossPosition + crossOffset);
  //         break;
  //       case Axis.vertical:
  //         childParentData.offset = new Offset(crossPosition + crossOffset, mainOffset);
  //         break;
  //     }
  //     mainOffset += _getMainSize(child);
  //   }
  //   switch (primaryAxis) {
  //     case Axis.horizontal:
  //       return new Size(
  //         maxExtent,
  //         crossPosition + maxCrossExtent,
  //       );
  //       break;
  //     case Axis.vertical:
  //       return new Size(
  //         crossPosition + maxCrossExtent,
  //         maxExtent,
  //       );
  //       break;
  //   }
  //   return null;
  // }

  @override
  bool hitTestChildren(HitTestResult result, { Point position }) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // TODO(ianh): clip if there is overflow
    // TODO(ianh): move the debug flex overflow paint logic somewhere common so it can be reused here
    defaultPaint(context, offset);
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('direction: $_direction');
    // description.add('primaryAlignment: $_primaryAlignment');
    // description.add('secondaryAlignment: $_secondaryAlignment');
  }
}
