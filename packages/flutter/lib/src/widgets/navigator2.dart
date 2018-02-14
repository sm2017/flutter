// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'basic.dart';
import 'binding.dart';
import 'focus_manager.dart';
import 'focus_scope.dart';
import 'framework.dart';
import 'overlay.dart';
import 'ticker_provider.dart';

typedef RouteFactory<T> = Route<T> Function<U>(RouteSettings<U> settings);
typedef RouteWrapper = Route<T> Function<T, U>({ @required WidgetBuilder builder, RouteSettings<U> settings });
typedef Future<bool> WillPopCallback();
typedef bool RoutePredicate(Route<dynamic> route);

enum RoutePopDisposition {
  pop,
  doNotPop,
  bubble,
}

abstract class Route<T> {
  NavigatorState get navigator;
  List<OverlayEntry> get overlayEntries;

  bool get isCurrent;
  bool get isFirst;
  bool get isActive;

  bool get willHandlePopInternally;
  Future<RoutePopDisposition> willPop();
  Future<T> get popped;
  T get currentResult;

  @protected
  @mustCallSuper
  void install(OverlayEntry insertionPoint) { }

  @protected
  TickerFuture didPush();

  @protected
  @mustCallSuper
  void didReplace(Route<dynamic> oldRoute) { }

  @protected
  @mustCallSuper
  bool didPop(T result) { }

  @protected
  @mustCallSuper
  void didComplete(T result) { }

  @protected
  @mustCallSuper
  void didPopNext(Route<dynamic> nextRoute) { }

  @protected
  @mustCallSuper
  void didChangeNext(Route<dynamic> nextRoute) { }

  @protected
  @mustCallSuper
  void didChangePrevious(Route<dynamic> previousRoute) { }

  @mustCallSuper
  @protected
  void dispose() { }
}

@immutable
@optionalTypeArgs
class RouteSettings<U> {
  const RouteSettings({
    this.name,
    this.isInitialRoute: false,
    this.arguments,
  });

  RouteSettings<U> copyWith({
    String name,
    bool isInitialRoute,
    U arguments,
  });

  final String name;

  final bool isInitialRoute;

  final U arguments;
}

class NavigatorObserver {
  NavigatorState get navigator;

  void didPush(Route<dynamic> route, Route<dynamic> previousRoute) { }
  void didPop(Route<dynamic> route, Route<dynamic> previousRoute) { }
  void didRemove(Route<dynamic> route, Route<dynamic> previousRoute) { }
  void didReplace(Route<dynamic> newRoute, Route<dynamic> oldRoute) { }

  void didStartUserGesture() { }
  void didStopUserGesture() { }
}

class Navigator extends StatefulWidget {
  const Navigator({
    Key key,
    this.initialRoute,
    this.onGenerateRoute,
    this.onUnknownRoute,
    this.observers,
    this.pages,
    this.onPopPage,
  }) : super(key: key);

  final String initialRoute;
  final RouteFactory onGenerateRoute;
  final RouteFactory onUnknownRoute;
  final List<NavigatorObserver> observers;

  final List<Page> pages;
  final ValueGetter<bool> onPopPage; // back button pressed when top thing on stack is from [pages]

  static const String defaultRouteName;

  @optionalTypeArgs
  static Future<T> pushNamed<T, U>(BuildContext context, String routeName, { U arguments });
  @optionalTypeArgs
  static Future<T> pushReplacementNamed<T, U>(BuildContext context, String routeName, { dynamic result, U arguments });
  @optionalTypeArgs
  static Future<T> popAndPushNamed<T, U>(BuildContext context, String routeName, { dynamic result, U arguments });
  @optionalTypeArgs
  static Future<T> pushNamedAndRemoveUntil<T, U>(BuildContext context, String routeName, RoutePredicate predicate, { U arguments });

  @optionalTypeArgs
  static Future<T> push<T>(BuildContext context, Route<T> route);
  @optionalTypeArgs
  static Future<T> pushReplacement(BuildContext context, Route<T> route, { dynamic result });
  @optionalTypeArgs
  static Future<T> pushAndRemoveUntil(BuildContext context, Route<T> newRoute, RoutePredicate predicate);

  @optionalTypeArgs
  static void replace<TO, T>(BuildContext context, { @required Route<TO> oldRoute, @required Route<T> newRoute });
  @optionalTypeArgs
  static void replaceRouteBelow<TA, T>(BuildContext context, { @required Route<TA> anchorRoute, Route<T> newRoute });

  static bool canPop(BuildContext context);
  @optionalTypeArgs
  static Future<bool> maybePop<T>(BuildContext context, [ T result ]);
  @optionalTypeArgs
  static bool pop<T>(BuildContext context, [ T result ]);
  static void popUntil(BuildContext context, RoutePredicate predicate);

  @optionalTypeArgs
  static void removeRoute<T>(BuildContext context, Route<T> route);
  @optionalTypeArgs
  static void removeRouteBelow<TA>(BuildContext context, Route<TA> anchorRoute);
  @optionalTypeArgs
  static void finalizeRoute<T>(BuildContext context, Route<T> route);

  static void replaceAllRoutes(BuildContext context, { @required List<Route<dynamic>> routes });

  static NavigatorState of(BuildContext context, { bool rootNavigator: false });

  @override
  NavigatorState createState() => new NavigatorState();
}

class NavigatorState extends State<Navigator> with TickerProviderStateMixin {
  final FocusScopeNode focusScopeNode = new FocusScopeNode();

  OverlayState get overlay;

  @optionalTypeArgs
  static Future<T> pushNamed<T, U>(String routeName, { U arguments });
  @optionalTypeArgs
  static Future<T> pushReplacementNamed<T, U>(String routeName, { dynamic result, U arguments });
  @optionalTypeArgs
  static Future<T> popAndPushNamed<T, U>(String routeName, { dynamic result, U arguments });
  @optionalTypeArgs
  static Future<T> pushNamedAndRemoveUntil<T, U>(String routeName, RoutePredicate predicate, { U arguments });

  @optionalTypeArgs
  static Future<T> push<T>(Route<T> route);
  @optionalTypeArgs
  static Future<T> pushReplacement(Route<T> route, { dynamic result });
  @optionalTypeArgs
  static Future<T> pushAndRemoveUntil(Route<T> newRoute, RoutePredicate predicate);

  @optionalTypeArgs
  static void replace<TO, T>({ @required Route<TO> oldRoute, @required Route<T> newRoute });
  @optionalTypeArgs
  static void replaceRouteBelow<TA, T>({ @required Route<TA> anchorRoute, Route<T> newRoute });

  static bool canPop(BuildContext context);
  @optionalTypeArgs
  static Future<bool> maybePop<T>([ T result ]);
  @optionalTypeArgs
  static bool pop<T>([ T result ]);
  static void popUntil(RoutePredicate predicate);

  @optionalTypeArgs
  static void removeRoute<T>(Route<T> route);
  @optionalTypeArgs
  static void removeRouteBelow<TA>(Route<TA> anchorRoute);
  @optionalTypeArgs
  static void finalizeRoute<T>(Route<T> route);

  static void replaceAllRoutes({ @required List<Route<dynamic>> routes });

  bool get userGestureInProgress;
  void didStartUserGesture();
  void didStopUserGesture();

  @override
  void initState() {
    super.initState();
    for (NavigatorObserver observer in widget.observers) {
      assert(observer.navigator == null);
      observer._navigator = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_history.isEmpty) {
      final String initialRouteName = widget.initialRoute ?? Navigator.defaultRouteName;
      RouteTable routeTable = RouteTable.of(context);
      assert(routeTable != null || initialRouteName == Navigator.defaultRouteName);
      if (routeTable != null) {
        routeTable.handle(initialRouteName);
      } else {
        push(_routeFor(new RouteSettings(name: initialRouteName, isInitialRoute: true)));
      }
      for (Route<dynamic> route in _history)
        _initialOverlayEntries.addAll(route.overlayEntries);
    }
  }

  // _routeFor uses onGenerateRoute/onUnknownRoute the same way as current _routeNamed
  // it requires that onGenerateRoute be non-null, at a minimum
  // it can assert that there's no RouteTable

  @override
  void didUpdateWidget(Navigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observers != widget.observers) {
      for (NavigatorObserver observer in oldWidget.observers)
        observer._navigator = null;
      for (NavigatorObserver observer in widget.observers) {
        assert(observer.navigator == null);
        observer._navigator = this;
      }
    }
    if (oldWidget.pages != widget.pages) {
      
    }
  }

  @override
  void dispose() {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    for (NavigatorObserver observer in widget.observers)
      observer._navigator = null;
    final List<Route<dynamic>> doomed = _poppedRoutes.toList()..addAll(_history);
    for (Route<dynamic> route in doomed)
      route.dispose();
    _poppedRoutes.clear();
    _history.clear();
    focusScopeNode.detach();
    super.dispose();
    assert(() { _debugLocked = false; return true; }());
  }

}



/* Common cases

   Wiki: adding and removing pages on the end, duplicates common

   Login: Removing a bunch of pages at the start, replacing with a new one or
   leaving with one previously added, or replacing with two so that there's a
   final welcome route on top of the main route.

   Dialog that has a route shown on top (e.g. main -> about dialog -> license
   screen)

   Creating a route should be asynchronous, so you can fetch images or other data
   before starting the animation.

   Auth gates: before showing the main page, check if you're logged in (async),
   then decide on the route to show based on that.

   Replacing routes with and without animation.

   Page router that converts incoming strings into lists of routes.
     * /product
     * /product/{id}
     * /product/{id}/config?color={color}

*/

class RouteTable extends InheritedWidget {
  RouteTable({
    Key key,
    this.routes,
    this.factory,
    Widget child,
  }) : assert(routes != null),
       assert(factory != null),
       super(key: key, child: child);

  final Map<String, WidgetBuilder> routes;

  final RouteWrapper factory;

  Route<T> createRoute<T, U>(BuildContext context, { RouteSettings<U> settings }) {
    return factory<T, U>(routes[settings.name]);
  }

  static RouteTable of(BuildContext context) {
    return context.ancestorInheritedElementForWidgetOfExactType(RouteTable)?.widget;
  }

  @override
  bool updateShouldNotify(RouteTable old) => false;
}



/// unrelated to PageView, PageController
@immutable
abstract class Page<T> {
  const Page({
    this.key,
    this.animateInsertion: true,
    this.animateRemoval: true,
  }) : assert(animateInsertion != null),
       assert(animateRemoval != null;

  final LocalKey key;

  final bool animateInsertion;

  final bool animateRemoval;

  bool canUpdate(Page other) {
    return other.runtimeType == runtimeType &&
           other.key == key;
  }

  Route<T> createRoute<U>(BuildContext context, RouteSettings<U> settings);
}

class NamedPage<T, U> extends Page<T> {
  const NamedPage(this.name, {
    LocalKey key,
    this.arguments,
    bool animateInsertion: true,
    bool animateRemoval: true,
  }) : super(
         key: key,
         animateInsertion: animateInsertion,
         animateRemoval: animateRemoval,
       );

  final String name;

  final U arguments;

  @override
  bool canUpdate(Page other) {
    if (!super.canUpdate(other))
      return false;
    assert(other.runtimeType == runtimeType);
    final NamedPage<T, U> typedOther = other;
    return typedOther.name == name
        && typedOther.arguments == arguments;
  }

  Route<T> createRoute<U>(BuildContext context, RouteSettings<U> settings) {
    assert(settings.name == name);
    return RouteTable.of(context).createRoute<T, U>(context, settings: settings);
  }
}

class CustomPage<T> extends Page<T> {
  const CustomPage(this.factory, {
    LocalKey key,
    bool animateInsertion: true,
    bool animateRemoval: true,
  }) : super(
         key: key,
         animateInsertion: animateInsertion,
         animateRemoval: animateRemoval,
       );

  final RouteFactory<T> factory;

  @override
  Route<T> createRoute<U>(BuildContext context, RouteSettings<U> settings) => factory<U>(settings);
}
