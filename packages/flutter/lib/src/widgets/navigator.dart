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

export 'package:flutter/foundation.dart' show TypedDictionary;

// Examples can assume:
// class MyScreen extends Placeholder { MyScreen({String title}); }
// class MyHomePage extends Placeholder { }
// NavigatorState navigator;

/// Creates a route for the given route settings.
///
/// Used by [Navigator.onGenerateRoute] and other callbacks that are used to
/// implement [Navigator.onGenerateRoute].
///
/// See also:
///
///  * [Navigator], which is where all the [Route]s end up.
///  * [DefaultParsedRouteHandler], which decomposes the
///    [Navigator.onGenerateRoute] API and provides different ways to think
///    about routes.
typedef Route<dynamic> RouteFactory(RouteSettings settings);

/// Creates a series of one or more routes.
///
/// Used by [Navigator.onGenerateInitialRoutes].
typedef List<Route<dynamic>> RouteListFactory(NavigatorState navigator, String initialRoute);

/// Signature for the [Navigator.popUntil] predicate argument.
typedef bool RoutePredicate(Route<dynamic> route);

/// Signature for a callback that verifies that it's OK to call [Navigator.pop].
///
/// Used by [Form.onWillPop], [ModalRoute.addScopedWillPopCallback],
/// [ModalRoute.removeScopedWillPopCallback], and [WillPopScope].
typedef Future<bool> WillPopCallback();

/// Signature for the [Navigator.onPopPage] callback.
///
/// The callback must call [Route.didPop] or [Route.didComplete] on the
/// specified route, and must [setState] so that the [Navigator] is updated with
/// a [Navigator.pages] list that no longer includes the corresponding [Page].
/// (Otherwise, the page will be interpreted as a new page to show when the
/// [Navigator.pages] list is next updated.)
typedef bool PagePopCallback(Route<dynamic> route, dynamic result);

/// Indicates whether the current route should be popped.
///
/// Used as the return value for [Route.willPop].
///
/// See also:
///
///  * [WillPopScope], a widget that hooks into the route's [Route.willPop]
///    mechanism.
enum RoutePopDisposition {
  /// Pop the route.
  ///
  /// If [Route.willPop] returns [pop] then the back button will actually pop
  /// the current route.
  pop,

  /// Do not pop the route.
  ///
  /// If [Route.willPop] returns [doNotPop] then the back button will be ignored.
  doNotPop,

  /// Delegate this to the next level of navigation.
  ///
  /// If [Route.willPop] return [bubble] then the back button will be handled
  /// by the [SystemNavigator], which will usually close the application.
  bubble,
}

/// Data that might be useful in constructing a [Route].
@immutable
class RouteSettings {
  /// Creates data used to construct routes.
  ///
  /// The [arguments] argument must not be null.
  const RouteSettings({
    this.name,
    this.arguments = TypedDictionary.empty,
  }) : assert(arguments != null);

  /// Creates a copy of this route settings object with the given fields
  /// replaced with the new values.
  RouteSettings copyWith({
    String name,
    TypedDictionary arguments,
  }) {
    return new RouteSettings(
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
    );
  }

  /// The name of the route (e.g., "/settings").
  ///
  /// If null, the route is anonymous.
  final String name;

  /// The arguments passed to this route.
  ///
  /// The arguments are key-value pairs, keyed by [Type], with values matching
  /// the [Type]. For example, a key may be `MyArgumentsObject`, with a value
  /// corresponding to an instance of `MyArgumentsObject`.
  final TypedDictionary arguments;

  @override
  String toString() => '$runtimeType("$name", $arguments)';
}

/// Describes the configuration of a [Route].
///
/// The type argument `T` is the corresponding [Route]'s return type, as
/// used by [Route.currentResult], [Route.popped], and [Route.didPop].
abstract class Page<T> extends RouteSettings {
  /// Initializes [key] for subclasses.
  ///
  /// The [arguments] argument must not be null.
  const Page({
    this.key,
    String name,
    TypedDictionary arguments = TypedDictionary.empty,
  }) : super(name: name, arguments: arguments);

  final LocalKey key;

  bool canUpdate(Page<dynamic> other) {
    return other.runtimeType == runtimeType &&
           other.key == key;
  }

  /// Create the [Route] that corresponds to this page.
  ///
  /// The created [Route] must have its [Route.settings] property set to this [Page].
  Route<T> createRoute(BuildContext context);
}

/// An abstraction for an entry managed by a [Navigator].
///
/// This class defines an abstract interface between the navigator and the
/// "routes" that are pushed on and popped off the navigator. Most routes have
/// visual affordances, which they place in the navigators [Overlay] using one
/// or more [OverlayEntry] objects.
///
/// See [Navigator] for more explanation of how to use a [Route] with
/// navigation, including code examples.
///
/// See [MaterialPageRoute] for a route that replaces the entire screen with a
/// platform-adaptive transition.
///
/// The type argument `T` is the route's return type, as used by
/// [currentResult], [popped], and [didPop]. The type `void` may be used if the
/// route does not return a value.
abstract class Route<T> {
  /// Initialize the [Route].
  ///
  /// If the [settings] are not provided, an empty [RouteSettings] object is
  /// used instead. If this [Route] was created from a [Page] in a
  /// [Navigator.pages] list (via [Page.createRoute]), then the [settings]
  /// argument must be set to that [Page].
  Route({
    RouteSettings settings,
  }) : this._settings = settings ?? const RouteSettings();

  /// The navigator that the route is in, if any.
  NavigatorState get navigator => _navigator;
  NavigatorState _navigator;

  /// The settings for this route.
  ///
  /// See [RouteSettings] for details.
  ///
  /// The settings can change during the route's lifetime. If the settings
  /// change, the route's overlays will be marked dirty (see
  /// [changedInternalState]).
  ///
  /// If the route is created from a [Page] in the [Navigator.pages] list, then
  /// this will be a [Page] subclass, and it will be updated each time the
  /// [Navigator] is rebuilt with a new
  /// [pages] list. Once the [Route] is removed from the history, this value
  /// stops updating (and remains with its last value).
  RouteSettings get settings => _settings;
  RouteSettings _settings;

  void _updateSettings(RouteSettings newSettings) {
    assert(newSettings != null);
    if (_settings != newSettings) {
      _settings = newSettings;
      changedInternalState();
    }
  }

  /// The entries this route has placed in the overlay.
  ///
  /// These are typically populated by [install], added to the [Overlay] by the
  /// [Navigator], and then removed by [dispose].
  ///
  /// There must be at least one entry in this list after [install] has been
  /// invoked.
  ///
  /// The [Navigator] will take care of keeping the entries together if the
  /// route is moved in the history.
  List<OverlayEntry> get overlayEntries => const <OverlayEntry>[];

  /// Called when the route is inserted into the navigator.
  ///
  /// Use this to populate [overlayEntries]. The [Navigator] will then add them
  /// to the [Overlay]. It's the responsibility of the [dispose] method on this
  /// [Route] object to remove them.
  ///
  /// The `isInitialRoute` argument indicates whether this route is part of the
  /// first batch of routes being pushed onto the [Navigator]. Typically this
  /// is used to skip any entrance transition during startup.
  @protected
  @mustCallSuper
  void install({ bool isInitialRoute = false }) { }

  /// Called after [install] when the route is pushed onto the navigator.
  ///
  /// The returned value resolves when the push transition is complete.
  ///
  /// The [didChangeNext] method is typically called immediately after this
  /// method is called.
  @protected
  TickerFuture didPush() => new TickerFuture.complete();

  /// Called after [install] when the route replaced another in the navigator.
  ///
  /// The [didChangeNext] method is typically called immediately after this
  /// method is called.
  @protected
  @mustCallSuper
  void didReplace() { }

  /// Returns whether calling [Navigator.maybePop] when this [Route] is current
  /// ([isCurrent]) should do anything.
  ///
  /// [Navigator.maybePop] is usually used instead of [pop] to handle the system
  /// back button.
  ///
  /// By default, if a [Route] is the first route in the history (i.e., if
  /// [isFirst]), it reports that pops should be bubbled
  /// ([RoutePopDisposition.bubble]). This behavior prevents the user from
  /// popping the first route off the history and being stranded at a blank
  /// screen; instead, the larger scope is popped (e.g. the application quits,
  /// so that the user returns to the previous application).
  ///
  /// In other cases, the default behaviour is to accept the pop
  /// ([RoutePopDisposition.pop]).
  ///
  /// The third possible value is [RoutePopDisposition.doNotPop], which causes
  /// the pop request to be ignored entirely.
  ///
  /// See also:
  ///
  ///  * [Form], which provides a [Form.onWillPop] callback that uses this
  ///    mechanism.
  ///  * [WillPopScope], another widget that provides a way to intercept the
  ///    back button.
  Future<RoutePopDisposition> willPop() async {
    return isFirst ? RoutePopDisposition.bubble : RoutePopDisposition.pop;
  }

  /// Whether calling [didPop] would return false.
  bool get willHandlePopInternally => false;

  /// When this route is popped (see [Navigator.pop]) if the result isn't
  /// specified or if it's null, this value will be used instead.
  ///
  /// This fallback is implemented by [didComplete]. This value is used if the
  /// argument to that method is null.
  T get currentResult => null;

  /// A future that completes when this route is popped off the navigator.
  ///
  /// The future completes with the value given to [Navigator.pop], if any, or
  /// else the value of [currentResult]. See [didComplete] for more discussion
  /// on this topic.
  Future<T> get popped => _popCompleter.future;
  final Completer<T> _popCompleter = new Completer<T>();

  /// A request was made to pop this route. If the route can handle it
  /// internally (e.g. because it has its own stack of internal state) then
  /// return false, otherwise return true (by returning the value of calling
  /// `super.didPop`). Returning false will prevent the default behavior of
  /// [NavigatorState.pop].
  ///
  /// When this function returns true, the navigator removes this route from
  /// the history but does not yet call [dispose]. Instead, it is the route's
  /// responsibility to call [NavigatorState.finalizeRoute], which will in turn
  /// call [dispose] on the route. This sequence lets the route perform an
  /// exit animation (or some other visual effect) after being popped but prior
  /// to being disposed.
  ///
  /// This method should call [didComplete] to resolve the [popped] future (and
  /// this is all that the default implementation does); routes should not wait
  /// for their exit animation to complete before doing so.
  ///
  /// See [popped], [didComplete], and [currentResult] for a discussion of the
  /// `result` argument.
  @protected
  @mustCallSuper
  bool didPop(T result) {
    didComplete(result);
    return true;
  }

  /// The route was popped or is otherwise being removed somewhat gracefully.
  ///
  /// This is called by [didPop] and in response to
  /// [NavigatorState.pushReplacement]. If [didPop] was not called, then the
  /// [Navigator.finalizeRoute] method must be called immediately, and no exit
  /// animation will run.
  ///
  /// The [popped] future is completed by this method. The `result` argument
  /// specifies the value that this future is completed with, unless it is null,
  /// in which case [currentResult] is used instead.
  ///
  /// This should be called before the pop animation, if any, takes place,
  /// though in some cases the animation may be driven by the user before the
  /// route is committed to being popped; this can in particular happen with the
  /// iOS-style back gesture. See [Navigator.didStartUserGesture].
  @protected
  @mustCallSuper
  void didComplete(T result) {
    _popCompleter.complete(result ?? currentResult);
  }

  /// The given route, which was above this one, has been popped off the
  /// navigator.
  ///
  /// This route is now the current route ([isCurrent] is now true), and there
  /// is no next route.
  @protected
  @mustCallSuper
  void didPopNext(Route<dynamic> nextRoute) { }

  /// This route's next route has changed to the given new route.
  ///
  /// This is called on a route whenever the next route changes for any reason,
  /// so long as it is in the history, including when a route is first added to
  /// a [Navigator] (e.g. by [Navigator.push]), except for cases when
  /// [didPopNext] would be called.
  ///
  /// The `nextRoute` argument will be null if there's no new next route (i.e.
  /// if [isCurrent] is true).
  @protected
  @mustCallSuper
  void didChangeNext(Route<dynamic> nextRoute) { }

  /// This route's previous route has changed to the given new route.
  ///
  /// This is called on a route whenever the previous route changes for any
  /// reason, so long as it is in the history, except for immediately after the
  /// route itself has been pushed (in which case [didPush] or [didReplace] will
  /// be called instead).
  ///
  /// The `previousRoute` argument will be null if there's no previous route
  /// (i.e. if [isFirst] is true).
  @protected
  @mustCallSuper
  void didChangePrevious(Route<dynamic> previousRoute) { }

  /// Called whenever the internal state of the route has changed.
  ///
  /// This should be called whenever [willHandlePopInternally], [didPop],
  /// [offstage], or other internal state of the route changes value. It is used
  /// by [ModalRoute], for example, to report the new information via its
  /// inherited widget to any children of the route.
  ///
  /// See also:
  ///
  ///  * [changedExternalState], which is called when the [Navigator] rebuilds.
  @protected
  @mustCallSuper
  void changedInternalState() { }

  /// Called whenever the [Navigator] has its widget rebuilt, to indicate that
  /// the route may wish to rebuild as well.
  ///
  /// This is called by the [Navigator] whenever the [NavigatorState]'s
  /// [widget] changes, for example because the [MaterialApp] has been rebuilt.
  /// This ensures that routes that directly refer to the state of the widget
  /// that built the [MaterialApp] will be notified when that widget rebuilds,
  /// since it would otherwise be difficult to notify the routes that state they
  /// depend on may have changed.
  ///
  /// See also:
  ///
  ///  * [changedInternalState], the equivalent but for changes to the internal
  ///    state of the route.
  @protected
  @mustCallSuper
  void changedExternalState() { }

  /// Discards any resources used by the object. After this is called, the
  /// object is not in a usable state and should be discarded.
  ///
  /// This method should only be called by the object's owner; typically the
  /// [Navigator] owns a route and so will call this method when the route is
  /// removed, after which the route is no longer referenced by the navigator.
  ///
  /// When this method is called, the route should remove its overlays and free
  /// any other resources.
  @mustCallSuper
  @protected
  void dispose() {
    _navigator = null;
  }

  /// Whether this route is the top-most route on the navigator.
  ///
  /// If this is true, then [isActive] is also true.
  bool get isCurrent {
    if (_navigator == null)
      return false;
    final _RouteEntry currentRouteEntry = _navigator._history.lastWhere(
      _RouteEntry.isPresentPredicate,
      orElse: () => null,
    );
    if (currentRouteEntry == null)
      return false;
    return currentRouteEntry.route == this;
  }

  /// Whether this route is the bottom-most route on the navigator.
  ///
  /// If this is true, then [Navigator.canPop] will return false if this route's
  /// [willHandlePopInternally] returns false.
  ///
  /// If [isFirst] and [isCurrent] are both true then this is the only route on
  /// the navigator (and [isActive] will also be true).
  bool get isFirst {
    if (_navigator == null)
      return false;
    final _RouteEntry currentRouteEntry = _navigator._history.firstWhere(
      _RouteEntry.isPresentPredicate,
      orElse: () => null,
    );
    if (currentRouteEntry == null)
      return false;
    return currentRouteEntry.route == this;
  }

  /// Whether this route is on the navigator.
  ///
  /// If the route is not only active, but also the current route (the top-most
  /// route), then [isCurrent] will also be true. If it is the first route (the
  /// bottom-most route), then [isFirst] will also be true.
  ///
  /// If a higher route is entirely opaque, then the route will be active but not
  /// rendered. It is even possible for the route to be active but for the stateful
  /// widgets within the route to not be instantiated. See [ModalRoute.maintainState].
  bool get isActive {
    if (_navigator == null)
      return false;
    return _navigator._history.where(_RouteEntry.isRoutePredicate(this)).isNotEmpty;
  }
}

/// An interface for observing the behavior of a [Navigator].
class NavigatorObserver {
  /// The navigator that the observer is observing, if any.
  NavigatorState get navigator => _navigator;
  NavigatorState _navigator;

  /// The [Navigator] pushed `route`.
  ///
  /// The route immediately below that one, and thus the previously active
  /// route, is `previousRoute`.
  void didPush(Route<dynamic> route, Route<dynamic> previousRoute) { }

  /// The [Navigator] popped `route`.
  ///
  /// The route immediately below that one, and thus the newly active
  /// route, is `previousRoute`.
  void didPop(Route<dynamic> route, Route<dynamic> previousRoute) { }

  /// The [Navigator] removed `route`.
  ///
  /// If only one route is being removed, then the route immediately below
  /// that one, if any, is `previousRoute`.
  ///
  /// If multiple routes are being removed, then the route below the
  /// bottommost route being removed, if any, is `previousRoute`, and this
  /// method will be called once for each removed route, from the topmost route
  /// to the bottommost route.
  void didRemove(Route<dynamic> route, Route<dynamic> previousRoute) { }

  /// The [Navigator] replaced `oldRoute` with `newRoute`.
  void didReplace({ Route<dynamic> newRoute, Route<dynamic> oldRoute }) { }

  /// The [Navigator]'s routes are being moved by a user gesture.
  ///
  /// For example, this is called when an iOS back gesture starts, and is used
  /// to disabled hero animations during such interactions.
  void didStartUserGesture() { }

  /// User gesture is no longer controlling the [Navigator].
  ///
  /// Paired with an earlier call to [didStartUserGesture].
  void didStopUserGesture() { }
}

/// A widget that manages a set of child widgets with a stack discipline.
///
/// Many apps have a navigator near the top of their widget hierarchy in order
/// to display their logical history using an [Overlay] with the most recently
/// visited pages visually on top of the older pages. Using this pattern lets
/// the navigator visually transition from one page to another by moving the widgets
/// around in the overlay. Similarly, the navigator can be used to show a dialog
/// by positioning the dialog widget above the current page.
///
/// ## Using the Navigator API
///
/// Mobile apps typically reveal their contents via full-screen elements
/// called "screens" or "pages". In Flutter these elements are called
/// routes and they're managed by a [Navigator] widget. The navigator
/// manages a stack of [Route] objects and provides methods for managing
/// the stack, like [Navigator.push] and [Navigator.pop].
///
/// ### Pages, Routes, and RouteSettings
///
/// A [Route] encapsulates the state of a screen or screen element (such as a
/// dialog or popup menu). It has a single immutable [RouteSettings] object
/// which specifies its name and initial arguments.
///
/// A [Page] is an immutable object which represents a potential [Route], in a
/// way analogous to how a [Widget] represents a potential [Element]. [Page] is
/// a subclass of [RouteSettings].
///
/// The [pages] property works in terms of [Page] objects, while the [Navigator]
/// API (the static methods on [Navigator] and the identically-named methods on
/// [NavigatorState], which you can obtain via [Navigator.of] or a [GlobalKey])
/// works in terms of [Route]s.
///
/// ### Displaying a full-screen route
///
/// Although you can create a navigator directly, it's most common to use the
/// navigator created by the [Router] which itself is created and configured by
/// a [WidgetsApp] or a [MaterialApp] widget. You can refer to that navigator
/// with [Navigator.of].
///
/// A [MaterialApp] is the simplest way to set things up. The [MaterialApp]'s
/// home becomes the route at the bottom of the [Navigator]'s stack. It is what
/// you see when the app is launched.
///
/// ```dart
/// void main() {
///   runApp(new MaterialApp(home: new MyAppHome()));
/// }
/// ```
///
/// To push a new route on the stack you can create an instance of
/// [MaterialPageRoute] with a builder function that creates whatever you
/// want to appear on the screen. For example:
///
/// ```dart
/// Navigator.push(context, new MaterialPageRoute<void>(
///   builder: (BuildContext context) {
///     return new Scaffold(
///       appBar: new AppBar(title: new Text('My Page')),
///       body: new Center(
///         child: new FlatButton(
///           child: new Text('POP'),
///           onPressed: () {
///             Navigator.pop(context);
///           },
///         ),
///       ),
///     );
///   },
/// ));
/// ```
///
/// The route defines its widget with a builder function instead of a
/// child widget because it will be built and rebuilt in different
/// contexts depending on when it's pushed and popped.
///
/// As you can see, the new route can be popped, revealing the app's home
/// page, with the Navigator's pop method:
///
/// ```dart
/// Navigator.pop(context);
/// ```
///
/// It usually isn't necessary to provide a widget that pops the Navigator
/// in a route with a [Scaffold] because the Scaffold automatically adds a
/// 'back' button to its AppBar. Pressing the back button causes
/// [Navigator.pop] to be called. On Android, pressing the system back
/// button does the same thing.
///
/// ### Using named navigator routes
///
/// Mobile apps often manage a large number of routes and it's often
/// easiest to refer to them by name. Route names, by convention,
/// use a path-like structure (for example, '/a/b/c').
/// The app's home page route is named '/' by default.
///
/// The [MaterialApp] can be created with a route table, a map of type
/// [Map<String, WidgetBuilder>], which maps from a route's name to a builder
/// function that will create it. The [MaterialApp] uses this map to create a
/// value for its navigator's [onGenerateRoute] callback.
///
/// ```dart
/// void main() {
///   runApp(new MaterialApp(
///     home: new MyAppHome(), // becomes the route named '/'
///     routes: <String, WidgetBuilder> {
///       '/a': (BuildContext context) => new MyScreen(title: 'page A'),
///       '/b': (BuildContext context) => new MyScreen(title: 'page B'),
///       '/c': (BuildContext context) => new MyScreen(title: 'page C'),
///     },
///   ));
/// }
/// ```
///
/// To show a route by name:
///
/// ```dart
/// Navigator.pushNamed(context, '/b');
/// ```
///
/// See [DefaultParsedRouteHandler] for details.
///
/// ### Routes can return a value
///
/// When a route is pushed to ask the user for a value, the value can be
/// returned via the [pop] method's result parameter.
///
/// Methods that push a route return a [Future]. The Future resolves when the
/// route is popped and the [Future]'s value is the [pop] method's `result`
/// parameter.
///
/// For example if we wanted to ask the user to press 'OK' to confirm an
/// operation we could `await` the result of [Navigator.push]:
///
/// ```dart
/// bool value = await Navigator.push(context, new MaterialPageRoute<bool>(
///   builder: (BuildContext context) {
///     return new Center(
///       child: new GestureDetector(
///         child: new Text('OK'),
///         onTap: () { Navigator.pop(context, true); }
///       ),
///     );
///   }
/// ));
/// ```
///
/// If the user presses 'OK' then value will be true. If the user backs
/// out of the route, for example by pressing the Scaffold's back button,
/// the value will be null.
///
/// When a route is used to return a value, the route's type parameter must
/// match the type of [pop]'s result. That's why we've used
/// `MaterialPageRoute<bool>` instead of `MaterialPageRoute<void>` or just
/// `MaterialPageRoute`. (If you prefer to not specify the types, though, that's
/// fine too.)
///
/// ### Popup routes
///
/// Routes don't have to obscure the entire screen. [PopupRoute]s cover the
/// screen with a [ModalRoute.barrierColor] that can be only partially opaque to
/// allow the current screen to show through. Popup routes are "modal" because
/// they block input to the widgets below.
///
/// There are functions which create and show popup routes. For
/// example: [showDialog], [showMenu], and [showModalBottomSheet]. These
/// functions return their pushed route's Future as described above.
/// Callers can await the returned value to take an action when the
/// route is popped, or to discover the route's value.
///
/// There are also widgets which create popup routes, like [PopupMenuButton] and
/// [DropdownButton]. These widgets create internal subclasses of PopupRoute
/// and use the Navigator's push and pop methods to show and dismiss them.
///
/// ### Custom routes
///
/// You can create your own subclass of one of the widget library route classes
/// like [PopupRoute], [ModalRoute], or [PageRoute], to control the animated
/// transition employed to show the route, the color and behavior of the route's
/// modal barrier, and other aspects of the route.
///
/// The [PageRouteBuilder] class makes it possible to define a custom route
/// in terms of callbacks. Here's an example that rotates and fades its child
/// when the route appears or disappears. This route does not obscure the entire
/// screen because it specifies `opaque: false`, just as a popup route does.
///
/// ```dart
/// Navigator.push(context, new PageRouteBuilder(
///   opaque: false,
///   pageBuilder: (BuildContext context, _, __) {
///     return new Center(child: new Text('My PageRoute'));
///   },
///   transitionsBuilder: (___, Animation<double> animation, ____, Widget child) {
///     return new FadeTransition(
///       opacity: animation,
///       child: new RotationTransition(
///         turns: new Tween<double>(begin: 0.5, end: 1.0).animate(animation),
///         child: child,
///       ),
///     );
///   }
/// ));
/// ```
///
/// The page route is built in two parts, the "page" and the
/// "transitions". The page becomes a descendant of the child passed to
/// the `buildTransitions` method. Typically the page is only built once,
/// because it doesn't depend on its animation parameters (elided with `_`
/// and `__` in this example). The transition is built on every frame
/// for its duration.
///
/// ### Selecting the initial route
///
/// If [initialRoute] is non-null, then the [onGenerateInitialRoutes] callback
/// will be called to determine routes to insert into the [Navigator] when it is
/// created.
///
/// Typically this is only used if [pages] is null. If both are specified, then
/// the [pages] routes are placed below those returned by the
/// [onGenerateInitialRoutes] callback.
///
/// The [Navigator.generateInitialRoutes] static method is the default value of
/// [onGenerateInitialRoutes]. It splits the route on `/` characters, then uses
/// [onGenerateRoute] for each component.
///
/// ## Nesting Navigators
///
/// An app can use more than one [Navigator]. Nesting one [Navigator] below
/// another [Navigator] can be used to create an "inner journey" such as tabbed
/// navigation, user registration, store checkout, or other independent journeys
/// that represent a subsection of your overall application.
///
/// ### Example
///
/// It is standard practice for iOS apps to use tabbed navigation where each
/// tab maintains its own navigation history. Therefore, each tab has its own
/// [Navigator], creating a kind of "parallel navigation."
///
/// In addition to the parallel navigation of the tabs, it is still possible to
/// launch full-screen pages that completely cover the tabs. For example: an
/// on-boarding flow, or an alert dialog. Therefore, there must exist a "root"
/// [Navigator] that sits above the tab navigation. As a result, each of the
/// tab's [Navigator]s are actually nested [Navigator]s sitting below a single
/// root [Navigator].
///
/// In practice, the nested [Navigator]s for tabbed navigation sit in the
/// [WidgetApp] and [CupertinoTabView] widgets, and so do not need to be
/// explicitly created or managed.
///
/// ### Sample Code
///
/// The following example demonstrates how a nested [Navigator] can be used to
/// present a standalone user registration journey.
///
/// Even though this example uses two [Navigator]s to demonstrate nested
/// [Navigator]s, a similar result is possible using only a single [Navigator].
///
/// ```dart
/// class MyApp extends StatelessWidget {
///  @override
///  Widget build(BuildContext context) {
///    return new MaterialApp(
///      // ...some parameters omitted...
///      // MaterialApp contains our top-level Navigator
///      initialRoute: '/',
///      routes: {
///        '/': (BuildContext context) => new HomePage(),
///        '/signup': (BuildContext context) => new SignUpPage(),
///      },
///    );
///  }
/// }
///
/// class SignUpPage extends StatelessWidget {
///  @override
///  Widget build(BuildContext context) {
///    // SignUpPage builds its own Navigator which ends up being a nested
///    // Navigator in our app.
///    return new Navigator(
///      initialRoute: 'signup/personal_info',
///      onGenerateRoute: (RouteSettings settings) {
///        WidgetBuilder builder;
///        switch (settings.name) {
///          case 'signup/personal_info':
///            // Assume CollectPersonalInfoPage collects personal info and then
///            // navigates to 'signup/choose_credentials'.
///            builder = (BuildContext _) => new CollectPersonalInfoPage();
///            break;
///          case 'signup/choose_credentials':
///            // Assume ChooseCredentialsPage collects new credentials and then
///            // invokes 'onSignupComplete()'.
///            builder = (BuildContext _) => new ChooseCredentialsPage(
///              onSignupComplete: () {
///                // Referencing Navigator.of(context) from here refers to the
///                // top level Navigator because SignUpPage is above the
///                // nested Navigator that it created. Therefore, this pop()
///                // will pop the entire "sign up" journey and return to the
///                // "/" route, AKA HomePage.
///                Navigator.of(context).pop();
///              },
///            );
///            break;
///          default:
///            throw new Exception('Invalid route: ${settings.name}');
///        }
///        return new MaterialPageRoute(builder: builder, settings: settings);
///      },
///    );
///  }
/// }
/// ```
///
/// [Navigator.of] operates on the nearest ancestor [Navigator] from the given
/// [BuildContext]. Be sure to provide a [BuildContext] below the intended
/// [Navigator], especially in large [build] methods where nested [Navigator]s
/// are created. The [Builder] widget can be used to access a [BuildContext] at
/// a desired location in the widget subtree.
///
/// ## Alternatives to the Navigator
///
/// Using a [Navigator] works well when the pages are only pushed and popped,
/// following a straight-forward pattern. The [Navigator] API starts to become
/// unwieldy when entire sequences of pages are replaced at once, when the
/// navigation path is non-linear, and when there are multiple simultaneous
/// parallel paths.
///
/// In such circumstances, rather than using the [Navigator] API directly,
/// consider using a [Router] with a custom [ParsedRouteHandler], providing
/// [pages] directly to the [Navigator] (or multiple [Navigator]s).
///
/// As the [pages] change, the [Navigator] will automatically update its
/// history, pushing and popping routes when appropriate, removing entire
/// sequences and replacing them when necessary. The [transitionDelegate] is
/// used to determine exactly how changes should be handled.
class Navigator extends StatefulWidget {
  /// Creates a widget that maintains a stack-based history of child widgets.
  const Navigator({
    Key key,
    this.pages = const <Page<dynamic>>[],
    this.onPopPage,
    this.initialRoute,
    this.onGenerateInitialRoutes = Navigator.defaultGenerateInitialRoutes,
    this.onGenerateRoute,
    this.onUnknownRoute,
    this.transitionDelegate = const DefaultNavigatorTransitionDelegate(),
    this.observers = const <NavigatorObserver>[],
  }) : assert(pages != null),
       assert(onGenerateInitialRoutes != null),
       assert(transitionDelegate != null),
       assert(observers != null),
       super(key: key);

  /// The list of pages with which to populate the history.
  ///
  /// Pages are turned into routes using [Page.createRoute] in a manner
  /// analogous to how [Widget]s are turned into [Element]s (and [State]s or
  /// [RenderObject]s) using [Widget.createElement] (and
  /// [StatefulWidget.createState] or [RenderObjectWidget.createRenderObject]).
  ///
  /// When this list is updated, the new list is compared to the previous
  /// list and the set of routes is updated accordingly.
  ///
  /// Some [Route]s do not correspond to [Page] objects, namely, those that are
  /// added to the history using the [Navigator] API ([push] and friends). A
  /// [Route] that does not correspond to a [Page] object is tied to the [Route]
  /// that _does_ correspond to a [Page] object that is below it in the history.
  ///
  /// Pages that are removed (and any routes that were pushed over those pages
  /// using [push] and friends, which are also removed) may be animated; this is
  /// controlled by the [transitionDelegate].
  ///
  /// If [initialRoute] is non-null when the widget is first created, then
  /// [onGenerateInitialRoutes] is used to generate routes that are above those
  /// corresponding to [pages] in the initial history.
  final List<Page<dynamic>> pages;

  /// Called when [pop] is invoked but the current [Route] corresponds to a
  /// [Page] found in the [pages] list.
  ///
  /// The `result` argument is the value with which the route is to complete
  /// (e.g. the value returned from a dialog).
  ///
  /// The [Navigator] widget should be rebuilt with a [pages] list that does not
  /// contain the [Page] for the given [Route]. The next time the [pages] list
  /// is updated, if the [Page] corresponding to this [Route] is still present,
  /// it will be interpreted as a new route to display.
  final PagePopCallback onPopPage;

  /// Called to generate a route for a given [RouteSettings] that isn't a [Page].
  ///
  /// This is used by [pushNamed] and friends, i.e. for routes that do not
  /// correspond to a [Page] object in [pages]. They create a [RouteSettings]
  /// object based on their arguments, call this method to generate the
  /// corresponding [Route], and then use [push] and friends to actually update
  /// the navigator's history.
  ///
  /// If this is null, then [onUnknownRoute], if provided, is used instead. If
  /// both return null, [pushNamed] and friends will fail. This is common in
  /// applications that use a [Router] with a custom [ParsedRouteHandler]
  /// instead of using the [DefaultParsedRouteHandler], a route table, and
  /// [pushNamed].
  final RouteFactory onGenerateRoute;

  /// Called to generate a route for a given [RouteSettings] that isn't a
  /// [Page], if [onGenerateRoute] could not do so.
  ///
  /// This callback is identical to [onGenerateRoute] but is called if that
  /// callback returned null.
  final RouteFactory onUnknownRoute;

  /// A suggested name for the default route of the application.
  ///
  /// This constant is not used by [Navigator] itself.
  ///
  /// See also:
  ///
  ///  * [dart:ui.Window.defaultRouteName], which reflects the route that the
  ///    application was started with.
  static const String defaultRouteName = '/';

  /// The name of the first route to show.
  ///
  /// By default, this is null, and the [pages] are used instead.
  ///
  /// If this is non-null, it is interpreted according to
  /// [onGenerateInitialRoutes], which defaults to
  /// [defaultGenerateInitialRoutes]. Pages listed in [pages] in the initial
  /// construction of the widget end up below those in the [initialRoute].
  ///
  /// To use [defaultGenerateInitialRoutes] when there is no particular initial
  /// route to show, pass [Navigator.defaultRouteName] as the value of this
  /// property. It is generally preferred to use [pages] and ignore
  /// [initialRoute], however.
  final String initialRoute;

  /// Called when the widget is created to generate the initial list of [Route]
  /// objects, if [initialRoute] is not null.
  ///
  /// Defaults to [defaultGenerateInitialRoutes].
  ///
  /// The [NavigatorState] and [initialRoute] will be passed to the callback.
  /// The callback must return a list of [Route] objects with which the history
  /// will be primed.
  ///
  /// If [pages] is also provided, then those routes will be placed below those
  /// provided by [onGenerateInitialRoutes].
  final RouteListFactory onGenerateInitialRoutes;

  final NavigatorTransitionDelegate transitionDelegate;

  /// A list of observers for this navigator.
  final List<NavigatorObserver> observers;

  /// Push a named route onto the navigator that most tightly encloses the given
  /// context.
  ///
  /// {@template flutter.widgets.navigator.pushNamed}
  /// The route name will be passed to that navigator's [onGenerateRoute]
  /// callback. The returned route will be pushed into the navigator.
  ///
  /// The new route and the previous route (if any) are notified (see
  /// [Route.didPush] and [Route.didChangeNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didPush]).
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the route.
  /// {@endtemplate}
  ///
  /// To use [pushNamed], an [onGenerateRoute] must be provided, either directly
  /// or via a specially-configured [Router]. See [DefaultRouteNameProvider] for
  /// details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _didPushButton() {
  ///   Navigator.pushNamed(context, '/nyc/1776');
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> pushNamed<T extends Object>(
    BuildContext context,
    String routeName, {
    TypedDictionary arguments = TypedDictionary.empty,
  }) {
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }

  /// Replace the current route of the navigator that most tightly encloses the
  /// given context by pushing the route named [routeName] and then disposing
  /// the previous route once the new route has finished animating in.
  ///
  /// {@template flutter.widgets.navigator.pushReplacementNamed}
  /// If non-null, `result` will be used as the result of the route that is
  /// removed; the future that had been returned from pushing that old route
  /// will complete with `result`. Routes such as dialogs or popup menus
  /// typically use this mechanism to return the value selected by the user to
  /// the widget that created their route. The type of `result`, if provided,
  /// must match the type argument of the class of the old route (`TO`).
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The route name will be passed to the navigator's [onGenerateRoute]
  /// callback. The returned route will be pushed into the navigator.
  ///
  /// The new route and the route below the removed route are notified (see
  /// [Route.didPush] and [Route.didChangeNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didReplace]). The removed route is notified once the
  /// new route has finished animating (see [Route.didComplete]). The removed
  /// route's exit animation is not run (see [popAndPushNamed] for a variant
  /// that does animated the removed route).
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the new route,
  /// and `TO` is the type of the return value of the old route.
  /// {@endtemplate}
  ///
  /// To use [pushReplacementNamed], an [onGenerateRoute] must be provided,
  /// either directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _showNext() {
  ///   Navigator.pushReplacementNamed(context, '/jouett/1781');
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> pushReplacementNamed<T extends Object, TO extends Object>(
    BuildContext context,
    String routeName, {
    TO result,
    TypedDictionary arguments = TypedDictionary.empty,
  }) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(routeName, result: result, arguments: arguments);
  }

  /// Pop the current route off the navigator that most tightly encloses the
  /// given context and push a named route in its place.
  ///
  /// {@template flutter.widgets.navigator.popAndPushNamed}
  /// The popping of the previous route is handled as per [pop].
  ///
  /// The new route's name will be passed to the navigator's [onGenerateRoute]
  /// callback. The returned route will be pushed into the navigator.
  ///
  /// The new route, the old route, and the route below the old route (if any)
  /// are all notified (see [Route.didPop], [Route.didComplete],
  /// [Route.didPopNext], [Route.didPush], and [Route.didChangeNext]). If the
  /// [Navigator] has any [Navigator.observers], they will be notified as well
  /// (see [NavigatorObserver.didPop] and [NavigatorObservers.didPush]). The
  /// animations for the pop and the push are performed simultaneously, so the
  /// route below may be briefly visible even if both the old route and the new
  /// route are opaque (see [TransitionRoute.opaque]).
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the new route,
  /// and `TO` is the return value type of the old route.
  /// {@endtemplate}
  ///
  /// To use [popAndPushNamed], an [onGenerateRoute] must be provided, either
  /// directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _selectNewYork() {
  ///   Navigator.popAndPushNamed(context, '/nyc/1776');
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> popAndPushNamed<T extends Object, TO extends Object>(
    BuildContext context,
    String routeName, {
    TO result,
    TypedDictionary arguments = TypedDictionary.empty,
  }) {
    return Navigator.of(context).popAndPushNamed<T, TO>(routeName, result: result, arguments: arguments);
  }

  /// Push the route with the given name onto the navigator that most tightly
  /// encloses the given context, and then remove all the previous routes until
  /// the `predicate` returns true.
  ///
  /// {@template flutter.widgets.navigator.pushNamedAndRemoveUntil}
  /// The predicate may be applied to the same route more than once if
  /// [Route.willHandlePopInternally] is true.
  ///
  /// To remove routes until a route with a certain name, use the
  /// [RoutePredicate] returned from [ModalRoute.withName].
  ///
  /// To remove all the routes below the pushed route, use a [RoutePredicate]
  /// that always returns false (e.g. `(Route<dynamic> route) => false`).
  ///
  /// The removed routes are removed without being completed, so this method
  /// does not take a return value argument.
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The new route's name (`routeName`) will be passed to the navigator's
  /// [onGenerateRoute] callback. The returned route will be pushed into the
  /// navigator.
  ///
  /// The new route and the route below the bottommost removed route (which
  /// becomes the route below the new route) are notified (see [Route.didPush]
  /// and [Route.didChangeNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObservers.didPush] and [NavigatorObservers.didRemove]). The
  /// removed routes are disposed, without being notified, once the new route
  /// has finished animating. The futures that had been returned from pushing
  /// those routes will not complete.
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the new route.
  /// {@endtemplate}
  ///
  /// To use [pushNamedAndRemoveUntil], an [onGenerateRoute] must be provided,
  /// either directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _resetToCalendar() {
  ///   Navigator.pushNamedAndRemoveUntil(context, '/calendar', ModalRoute.withName('/'));
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> pushNamedAndRemoveUntil<T extends Object>(
    BuildContext context,
    String newRouteName,
    RoutePredicate predicate, {
    TypedDictionary arguments = TypedDictionary.empty,
  }) {
    return Navigator.of(context).pushNamedAndRemoveUntil<T>(newRouteName, predicate, arguments: arguments);
  }

  /// Push the given route onto the navigator that most tightly encloses the
  /// given context.
  ///
  /// {@template flutter.widgets.navigator.push}
  /// The new route and the previous route (if any) are notified (see
  /// [Route.didPush] and [Route.didChangeNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didPush]).
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the route.
  /// {@endtemplate}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _openMyScreen() {
  ///   Navigator.push(context, new MaterialPageRoute(builder: (BuildContext context) => new MyScreen()));
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> push<T extends Object>(BuildContext context, Route<T> route) {
    return Navigator.of(context).push(route);
  }

  /// Replace the current route of the navigator that most tightly encloses the
  /// given context by pushing the given route and then disposing the previous
  /// route once the new route has finished animating in.
  ///
  /// {@template flutter.widgets.navigator.pushReplacement}
  /// If non-null, `result` will be used as the result of the route that is
  /// removed; the future that had been returned from pushing that old route will
  /// complete with `result`. Routes such as dialogs or popup menus typically
  /// use this mechanism to return the value selected by the user to the widget
  /// that created their route. The type of `result`, if provided, must match
  /// the type argument of the class of the old route (`TO`).
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The new route and the route below the removed route are notified (see
  /// [Route.didPush] and [Route.didChangeNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didReplace]). The removed route is notified once the
  /// new route has finished animating (see [Route.didComplete]).
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the new route,
  /// and `TO` is the type of the return value of the old route.
  /// {@endtemplate}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _completeLogin() {
  ///   Navigator.pushReplacement(
  ///       context, new MaterialPageRoute(builder: (BuildContext context) => new MyHomePage()));
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> pushReplacement<T extends Object, TO extends Object>(BuildContext context, Route<T> newRoute, { TO result }) {
    return Navigator.of(context).pushReplacement<T, TO>(newRoute, result: result);
  }

  /// Push the given route onto the navigator that most tightly encloses the
  /// given context, and then remove all the previous routes until the
  /// `predicate` returns true.
  ///
  /// {@template flutter.widgets.navigator.pushAndRemoveUntil}
  /// The predicate may be applied to the same route more than once if
  /// [Route.willHandlePopInternally] is true.
  ///
  /// To remove routes until a route with a certain name, use the
  /// [RoutePredicate] returned from [ModalRoute.withName].
  ///
  /// To remove all the routes below the pushed route, use a [RoutePredicate]
  /// that always returns false (e.g. `(Route<dynamic> route) => false`).
  ///
  /// The removed routes are removed without being completed, so this method
  /// does not take a return value argument.
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The new route and the route below the bottommost removed route (which
  /// becomes the route below the new route) are notified (see [Route.didPush]
  /// and [Route.didChangeNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObservers.didPush] and [NavigatorObservers.didRemove]). The
  /// removed routes are disposed, without being notified, once the new route
  /// has finished animating. The futures that had been returned from pushing
  /// those routes will not complete.
  ///
  /// Ongoing gestures within the current route are canceled when a new route is
  /// pushed.
  ///
  /// Returns a [Future] that completes to the `result` value passed to [pop]
  /// when the pushed route is popped off the navigator.
  ///
  /// The `T` type argument is the type of the return value of the new route.
  /// {@endtemplate}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _finishAccountCreation() {
  ///   Navigator.pushAndRemoveUntil(
  ///     context,
  ///     new MaterialPageRoute(builder: (BuildContext context) => new MyHomePage()),
  ///     ModalRoute.withName('/'),
  ///   );
  /// }
  /// ```
  @optionalTypeArgs
  static Future<T> pushAndRemoveUntil<T extends Object>(BuildContext context, Route<T> newRoute, RoutePredicate predicate) {
    return Navigator.of(context).pushAndRemoveUntil<T>(newRoute, predicate);
  }

  /// Replaces a route on the navigator that most tightly encloses the given
  /// context with a new route.
  ///
  /// {@template flutter.widgets.navigator.replace}
  /// The old route must not be current visible, as this method skips the
  /// animations and therefore the removal would be jarring if it was visible.
  /// To replace the top-most route, consider [pushReplacement] instead, which
  /// _does_ animate the new route, and delays removing the old route until the
  /// new route has finished animating.
  ///
  /// The removed route is removed without being completed, so this method does
  /// not take a return value argument.
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The new route, the route below the new route (if any), and the route above
  /// the new route, are all notified (see [Route.didReplace],
  /// [Route.didChangeNext], and [Route.didChangePrevious]). If the [Navigator]
  /// has any [Navigator.observers], they will be notified as well (see
  /// [NavigatorObservers.didReplace]). The removed route is disposed without
  /// being notified. The future that had been returned from pushing that routes
  /// will not complete.
  ///
  /// This can be useful in combination with [removeRouteBelow] when building a
  /// non-linear user experience.
  ///
  /// The `T` type argument is the type of the return value of the new route.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [replaceRouteBelow], which is the same but identifies the route to be
  ///    removed by reference to the route above it, rather than directly.
  @optionalTypeArgs
  static void replace<T extends Object>(BuildContext context, { @required Route<dynamic> oldRoute, @required Route<T> newRoute }) {
    return Navigator.of(context).replace<T>(oldRoute: oldRoute, newRoute: newRoute);
  }

  /// Replaces a route on the navigator that most tightly encloses the given
  /// context with a new route. The route to be replaced is the one below the
  /// given `anchorRoute`.
  ///
  /// {@template flutter.widgets.navigator.replaceRouteBelow}
  /// The old route must not be current visible, as this method skips the
  /// animations and therefore the removal would be jarring if it was visible.
  /// To replace the top-most route, consider [pushReplacement] instead, which
  /// _does_ animate the new route, and delays removing the old route until the
  /// new route has finished animating.
  ///
  /// The removed route is removed without being completed, so this method does
  /// not take a return value argument.
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The new route, the route below the new route (if any), and the route above
  /// the new route, are all notified (see [Route.didReplace],
  /// [Route.didChangeNext], and [Route.didChangePrevious]). If the [Navigator]
  /// has any [Navigator.observers], they will be notified as well (see
  /// [NavigatorObservers.didReplace]). The removed route is disposed without
  /// being notified. The future that had been returned from pushing that routes
  /// will not complete.
  ///
  /// The `T` type argument is the type of the return value of the new route.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [replace], which is the same but identifies the route to be removed
  ///    directly.
  @optionalTypeArgs
  static void replaceRouteBelow<T extends Object>(BuildContext context, { @required Route<dynamic> anchorRoute, Route<T> newRoute }) {
    return Navigator.of(context).replaceRouteBelow<T>(anchorRoute: anchorRoute, newRoute: newRoute);
  }

  /// Whether the navigator that most tightly encloses the given context can be
  /// popped.
  ///
  /// {@template flutter.widgets.navigator.canPop}
  /// The initial route cannot be popped off the navigator, which implies that
  /// this function returns true only if popping the navigator would not remove
  /// the initial route.
  ///
  /// If there is no [Navigator] in scope, returns false.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [Route.isFirst], which returns true for routes for which [canPop]
  ///    returns false.
  static bool canPop(BuildContext context) {
    final NavigatorState navigator = Navigator.of(context, nullOk: true);
    return navigator != null && navigator.canPop();
  }

  /// Consults the current route's [Route.willPop] method, and acts accordingly,
  /// potentially popping the route as a result; returns whether the pop request
  /// should be considered handled.
  ///
  /// {@template flutter.widgets.navigator.maybePop}
  /// If [Route.willPop] returns [RoutePopDisposition.pop], then the [pop]
  /// method is called, and this method returns true, indicating that it handled
  /// the pop request.
  ///
  /// If [Route.willPop] returns [RoutePopDisposition.doNotPop], then this
  /// method returns true, but does not do anything beyond that.
  ///
  /// If [Route.willPop] returns [RoutePopDisposition.bubble], then this method
  /// returns false, and the caller is responsible for sending the request to
  /// the containing scope (e.g. by closing the application).
  ///
  /// This method is typically called for a user-initiated [pop]. For example on
  /// Android it's called by the binding for the system's back button.
  ///
  /// The `T` type argument is the type of the return value of the current
  /// route. (Typically this isn't known; consider specifying `dynamic` or
  /// `Null`.)
  /// {@endtemplate}
  ///
  /// See also:
  ///
  /// * [Form], which provides an `onWillPop` callback that enables the form
  ///   to veto a [pop] initiated by the app's back button.
  /// * [ModalRoute], which provides a `scopedWillPopCallback` that can be used
  ///   to define the route's `willPop` method.
  @optionalTypeArgs
  static Future<bool> maybePop<T extends Object>(BuildContext context, [ T result ]) {
    return Navigator.of(context).maybePop<T>(result);
  }

  /// Pop the top-most route off the navigator that most tightly encloses the
  /// given context.
  ///
  /// {@template flutter.widgets.navigator.pop}
  /// The route's approriate _handler_ (as defined below) is called, passing it
  /// the _result of the route_ (also as defined below). If the handler returns
  /// false, then the route is expected to have popped some internal state, and
  /// nothing further is done; see e.g. [LocalHistoryRoute]. If the handler
  /// returns true, then the route is scheduled for removal.
  ///
  /// _Handler_: If the route in question was added using [Navigator.pages], the
  /// [Navigator.onPopPage] callback is used as the handler (typically this
  /// calls [Route.didPop] then, if the route was indeed popped, uses
  /// [State.setState] to update the [Navigator.pages] list to omit the now
  /// popped route); otherwise, the current route's [Route.didPop] method is
  /// used directly, and the route will be removed directly if necessary.
  ///
  /// _Result of the route_: If non-null, `result` will be used as the result of
  /// the route that is popped. If `result` is null, then the
  /// [Route.currentResult] value is used instead (see [Route.didComplete]). The
  /// future that had been returned from pushing the now popped route will
  /// complete with this result. Routes such as dialogs or popup menus typically
  /// use this mechanism to return the value selected by the user to the widget
  /// that created their route.
  ///
  /// The popped route and the route below it are notified (see [Route.didPop],
  /// [Route.didComplete], and [Route.didPopNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didPop]).
  ///
  /// The `T` type argument is the type of the return value of the popped route.
  /// The type of `result`, if provided, must match the type argument of the
  /// class of the popped route (`T`).
  /// {@endtemplate}
  ///
  /// ## Sample code
  ///
  /// Typical usage for closing a route is as follows:
  ///
  /// ```dart
  /// void _close() {
  ///   Navigator.pop(context);
  /// }
  /// ```
  ///
  /// A dialog box might be closed with a result:
  ///
  /// ```dart
  /// void _accept() {
  ///   Navigator.pop(context, true); // dialog returns true
  /// }
  /// ```
  @optionalTypeArgs
  static void pop<T extends Object>(BuildContext context, [ T result ]) {
    Navigator.of(context).pop<T>(result);
  }

  /// Calls [pop] repeatedly on the navigator that most tightly encloses the
  /// given context until the predicate returns true.
  ///
  /// {@template flutter.widgets.navigator.popUntil}
  /// The predicate may be applied to the same route more than once if
  /// [Route.willHandlePopInternally] is true.
  ///
  /// To pop until a route with a certain name, use the [RoutePredicate]
  /// returned from [ModalRoute.withName].
  ///
  /// The routes are closed with null as their `return` value.
  ///
  /// See [pop] for more details of the semantics of popping a route.
  /// {@endtemplate}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _logout() {
  ///   Navigator.popUntil(context, ModalRoute.withName('/login'));
  /// }
  /// ```
  static void popUntil(BuildContext context, RoutePredicate predicate) {
    Navigator.of(context).popUntil(predicate);
  }

  /// Immediately remove `route` from the navigator that most tightly encloses
  /// the given context, and [Route.dispose] it.
  ///
  /// {@template flutter.widgets.navigator.removeRoute}
  /// The removed route is removed without being completed, so this method does
  /// not take a return value argument. No animations are run as a result of
  /// this method call.
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The routes below and above the removed route are notified (see
  /// [Route.didChangeNext] and [Route.didChangePrevious]). If the [Navigator]
  /// has any [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didRemove]). The removed route is disposed without
  /// being notified. The future that had been returned from pushing that routes
  /// will not complete.
  ///
  /// The given `route` must be in the history; this method will throw an
  /// exception if it is not.
  ///
  /// Ongoing gestures within the current route are canceled.
  /// {@endtemplate}
  ///
  /// This method is used, for example, to instantly dismiss dropdown menus that
  /// are up when the screen's orientation changes.
  static void removeRoute(BuildContext context, Route<dynamic> route) {
    return Navigator.of(context).removeRoute(route);
  }

  /// Immediately remove a route from the navigator that most tightly encloses
  /// the given context, and [Route.dispose] it. The route to be replaced is the
  /// one below the given `anchorRoute`.
  ///
  /// {@template flutter.widgets.navigator.removeRouteBelow}
  /// The removed route is removed without being completed, so this method does
  /// not take a return value argument. No animations are run as a result of
  /// this method call.
  ///
  /// Only routes that were added using the [Navigator] API (as opposed to using
  /// [Navigator.pages]) can be removed this way. Trying to remove a route that
  /// was added using [Navigator.pages] will throw.
  ///
  /// The routes below and above the removed route are notified (see
  /// [Route.didChangeNext] and [Route.didChangePrevious]). If the [Navigator]
  /// has any [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didRemove]). The removed route is disposed without
  /// being notified. The future that had been returned from pushing that routes
  /// will not complete.
  ///
  /// The given `anchorRoute` must be in the history and must have a route below
  /// it; this method will throw an exception if it is not or does not.
  ///
  /// Ongoing gestures within the current route are canceled.
  /// {@endtemplate}
  static void removeRouteBelow(BuildContext context, Route<dynamic> anchorRoute) {
    return Navigator.of(context).removeRouteBelow(anchorRoute);
  }

  /// The state from the closest instance of this class that encloses the given context.
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// Navigator.of(context)
  ///   ..pop()
  ///   ..pop()
  ///   ..pushNamed('/settings');
  /// ```
  ///
  /// If `rootNavigator` is set to true, the state from the furthest instance of
  /// this class is given instead. Useful for pushing contents above all subsequent
  /// instances of [Navigator].
  static NavigatorState of(
    BuildContext context, {
      bool rootNavigator = false,
      bool nullOk = false,
    }) {
    final NavigatorState navigator = rootNavigator
        ? context.rootAncestorStateOfType(const TypeMatcher<NavigatorState>())
        : context.ancestorStateOfType(const TypeMatcher<NavigatorState>());
    assert(() {
      if (navigator == null && !nullOk) {
        throw new FlutterError(
          'Navigator operation requested with a context that does not include a Navigator.\n'
          'The context used to push or pop routes from the Navigator must be that of a '
          'widget that is a descendant of a Navigator widget.'
        );
      }
      return true;
    }());
    return navigator;
  }

  /// Turn a route name into a set of [Route] objects.
  ///
  /// This is the default value of [onGenerateInitialRoutes], which is used if
  /// [initialRoute] is not null.
  ///
  /// If this string contains any `/` characters, then the string is split on
  /// those characters and substrings from the start of the string up to each
  /// such character are, in turn, used as routes to push.
  ///
  /// For example, if the route `/stocks/HOOLI` was used as the [initialRoute],
  /// then the [Navigator] would push the following routes on startup: `/`,
  /// `/stocks`, `/stocks/HOOLI`. This enables deep linking while allowing the
  /// application to maintain a predictable route history.
  static List<Route<dynamic>> defaultGenerateInitialRoutes(NavigatorState navigator, String initialRouteName) {
    final List<Route<dynamic>> result = <Route<dynamic>>[];
    if (initialRouteName.startsWith('/') && initialRouteName.length > 1) {
      initialRouteName = initialRouteName.substring(1); // strip leading '/'
      assert(Navigator.defaultRouteName == '/');
      List<String> debugRouteNames;
      assert(() {
        debugRouteNames = <String>[ Navigator.defaultRouteName ];
        return true;
      }());
      navigator._routeNamed<dynamic>(Navigator.defaultRouteName, arguments: TypedDictionary.empty, allowNull: true);
      final List<String> routeParts = initialRouteName.split('/');
      if (initialRouteName.isNotEmpty) {
        String routeName = '';
        for (String part in routeParts) {
          routeName += '/$part';
          assert(() {
            debugRouteNames.add(routeName);
            return true;
          }());
          result.add(navigator._routeNamed<dynamic>(routeName, arguments: TypedDictionary.empty, allowNull: true));
        }
      }
      if (result.contains(null)) {
        assert(() {
          FlutterError.reportError(
            new FlutterErrorDetails(
              exception:
                'Could not navigate to initial route.\n'
                'The requested route name was: "/$initialRouteName"\n'
                'The following routes were therefore attempted:\n'
                ' * ${debugRouteNames.join("\n * ")}\n'
                'This resulted in the following objects:\n'
                ' * ${result.join("\n * ")}\n'
                'One or more of those objects was null, and therefore the initial route specified will be '
                'ignored and "${Navigator.defaultRouteName}" will be used instead.'
            ),
          );
          return true;
        }());
        result.clear();
      }
    } else if (initialRouteName != Navigator.defaultRouteName) {
      // If initialRouteName wasn't '/', then we try to get it with allowNull:true, so that if that fails,
      // we fall back to '/' (without allowNull:true, see below).
      result.add(navigator._routeNamed<dynamic>(initialRouteName, arguments: TypedDictionary.empty, allowNull: true));
    }
    if (result.isEmpty)
      result.add(navigator._routeNamed<dynamic>(Navigator.defaultRouteName, arguments: TypedDictionary.empty));
    return result;
  }

  @override
  NavigatorState createState() => new NavigatorState();
}

// The _RouteLifecycle state machine (only goes down):
//
//    [creation of a _RouteEntry]
//      |      |      |       |
//      |   newPage*  |       |
//      |   /    \    |       |
//      |  /      \   |       |
//      | |        |  |       |
//     push*     replace*  initial*
//       |          |         |
//        \        /         /
//      pushing#  /         /
//          \    /         /
//           \  /         /
//           idle--------+
//           /  \
//          /    \
//        pop*  remove*
//        /        \
//       /       removing#
//     popping#       |
//      |             |
//   [finalizeRoute]  |
//              \     |
//              dispose*
//                 |
//                 |
//              disposed
//                 |
//                 |
//  [_RouteEntry garbage collected]
//          (terminal state)
//
// * These states are transient; as soon as _flushHistoryUpdates is run the
//   route entry will exit that state.
// # These states await futures or other events, then transition automatically.
enum _RouteLifecycle {
  // routes that are present:
  newPage, // a route added via pages
  push, // we'll want to run install, didPush, etc; a route added via push() and friends
  replace, // we'll want to run install, didReplace, etc; a route added via replace() and friends
  initial, // we'll want to run install; a route created by onGenerateInitialRoutes or by the initial widget.pages
  pushing, // we're waiting for the future from didPush to complete
  idle, // route is being harmless
  // routes that are not present:
  pop, // we'll want to call didPop
  popping, // we're waiting for the route to call finalizeRoute to switch to dispose
  remove, // we'll want to run didReplace/didRemove etc
  removing, // we are waiting for subsequent routes to be done animating, then will switch to dispose
  dispose, // we will dispose the route momentarily
  disposed, // we have disposed the route
}

typedef bool _RouteEntryPredicate(_RouteEntry entry);

class _RouteEntry {
  _RouteEntry(
    this.route, {
    @required _RouteLifecycle initialState,
  }) : assert(route != null),
       assert(initialState != null),
       assert(initialState == _RouteLifecycle.initial || initialState == _RouteLifecycle.push || initialState == _RouteLifecycle.replace),
       currentState = initialState; // ignore: prefer_initializing_formals

  final Route<dynamic> route;

  bool get hasPage => route.settings is Page;

  _RouteLifecycle currentState;
  Route<dynamic> lastAnnouncedNextRoute;
  Route<dynamic> lastAnnouncedPreviousRoute;

  OverlayEntry get lastOverlayEntry => route.overlayEntries.isEmpty ? null : route.overlayEntries.last;

  void handleAddition({ @required NavigatorState navigator, OverlayEntry previousOverlayEntry, @required Route<dynamic> next, @required Route<dynamic> previous }) {
    assert(currentState == _RouteLifecycle.initial || currentState == _RouteLifecycle.push || currentState == _RouteLifecycle.replace);
    assert(navigator != null);
    assert(navigator._debugLocked);
    assert(route._navigator == null);
    route._navigator = navigator;
    route.install(isInitialRoute: currentState == _RouteLifecycle.initial);
    assert(route.overlayEntries.isNotEmpty);
    if (currentState == _RouteLifecycle.push) {
      currentState = _RouteLifecycle.pushing;
      route.didPush().whenCompleteOrCancel(() {
        if (currentState == _RouteLifecycle.pushing) {
          currentState = _RouteLifecycle.idle;
          assert(!navigator._debugLocked);
          assert(() { navigator._debugLocked = true; return true; }());
          navigator._flushHistoryUpdates();
          assert(() { navigator._debugLocked = false; return true; }());
        }
      });
    } else {
      assert(currentState == _RouteLifecycle.initial || currentState == _RouteLifecycle.replace);
      if (currentState == _RouteLifecycle.replace)
        route.didReplace();
      currentState = _RouteLifecycle.idle;
    }
    route.didChangeNext(next);
    lastAnnouncedNextRoute = next;
    lastAnnouncedPreviousRoute = previous;
    if (currentState == _RouteLifecycle.push) {
      for (NavigatorObserver observer in navigator.widget.observers)
        observer.didPush(route, previous);
    } else if (currentState == _RouteLifecycle.replace) {
      for (NavigatorObserver observer in navigator.widget.observers)
        observer.didReplace(newRoute: route, oldRoute: previous);
    }
  }

  void handlePop({ @required NavigatorState navigator, @required Route<dynamic> previous }) {
    assert(navigator != null);
    assert(navigator._debugLocked);
    assert(route._navigator == navigator);
    currentState = _RouteLifecycle.popping;
    for (NavigatorObserver observer in navigator.widget.observers)
      observer.didPop(route, previous);
  }

  void handleRemoval({ @required NavigatorState navigator, @required Route<dynamic> previous }) {
    assert(navigator != null);
    assert(navigator._debugLocked);
    assert(route._navigator == navigator);
    currentState = _RouteLifecycle.removing;
    for (NavigatorObserver observer in navigator.widget.observers)
      observer.didRemove(route, previous);
  }

  // Called between builds when the imperative API wants this pageless route to
  // be popped, and during a build for routes _with_ pages when we discover the
  // declarative API has removed the route.
  void pop<T>(T result) {
    assert(isPresent);
    route.didPop(result);
    assert(route._popCompleter.isCompleted); // implies didComplete was called
    currentState = _RouteLifecycle.pop;
  }

  // Called between builds when onPopPage has been called for a route with a
  // page. The didPop and didComplete methods have already been called.
  void markPopped() {
    assert(isPresent);
    assert(route._popCompleter.isCompleted); // implies didComplete was called
    currentState = _RouteLifecycle.pop;
  }

  void remove<T>([ T result ]) {
    if (currentState.index >= _RouteLifecycle.remove.index)
      return;
    assert(isPresent);
    route.didComplete(result);
    assert(route._popCompleter.isCompleted); // implies didComplete was called
    currentState = _RouteLifecycle.remove;
  }

  void finalize() {
    assert(currentState.index < _RouteLifecycle.dispose.index);
    currentState = _RouteLifecycle.dispose;
  }

  void dispose() {
    assert(currentState.index < _RouteLifecycle.disposed.index);
    route.dispose();
    currentState = _RouteLifecycle.disposed;
  }

  bool canUpdateFrom(Page<dynamic> page) {
    if (currentState.index > _RouteLifecycle.idle.index)
      return false;
    if (!hasPage)
      return false;
    final Page<dynamic> routePage = route.settings;
    return page.canUpdate(routePage);
  }

  bool get isPresent => currentState.index <= _RouteLifecycle.idle.index;

  static final _RouteEntryPredicate isPresentPredicate = (_RouteEntry entry) => entry.isPresent;

  static _RouteEntryPredicate isRoutePredicate(Route<dynamic> route) {
    return (_RouteEntry entry) => entry.route == route;
  }
}

// A record used only during [NavigatorState._updatePages] for
// tracking routes that are likely about to be removed.
class _SkippedRouteEntry {
  _SkippedRouteEntry({ @required this.entry, @required this.savePoint }) : assert(entry.hasPage);

  // The route that is probably being removed.
  final _RouteEntry entry;

  // The route after which we'll insert ourselves as we await our eventual
  // demise if we are not rescued.
  //
  // The null value means at the start of the history.
  final _RouteEntry savePoint;

  // The list of routes whose lifecycle has been pinned to ours (these are
  // routes without pages).
  final List<_RouteEntry> subsidiaryEntries = <_RouteEntry>[];

  void remove() {
    entry.remove<Null>();
    for (_RouteEntry subsidiaryEntry in subsidiaryEntries)
      subsidiaryEntry.remove<Null>();
  }
}

class NavigatorTransitionDelegate {
  const NavigatorTransitionDelegate();
  // xxx
}

class DefaultNavigatorTransitionDelegate extends NavigatorTransitionDelegate {
  const DefaultNavigatorTransitionDelegate();
  // xxx
}

/// The state for a [Navigator] widget.
class NavigatorState extends State<Navigator> with TickerProviderStateMixin {
  final List<_RouteEntry> _history = <_RouteEntry>[];

  bool _debugLocked = false; // used to prevent re-entrant calls to push, pop, and friends

  /// The [FocusScopeNode] for the [FocusScope] that encloses the routes.
  final FocusScopeNode focusScopeNode = new FocusScopeNode();

  /// The overlay this navigator uses for its visual presentation.
  OverlayState get overlay => _overlayKey.currentState;
  final GlobalKey<OverlayState> _overlayKey = new GlobalKey<OverlayState>();

  Iterable<OverlayEntry> get _allRouteOverlayEntries sync* {
    for (_RouteEntry entry in _history)
      yield* entry.route.overlayEntries;
  }

  @override
  void initState() {
    super.initState();
    for (NavigatorObserver observer in widget.observers) {
      assert(observer.navigator == null);
      observer._navigator = this;
    }
    _updatePages();
    if (widget.initialRoute != null) {
      _history.addAll(
        widget.onGenerateInitialRoutes(this, widget.initialRoute)
          .map((Route<dynamic> route) => new _RouteEntry(
            route,
            initialState: _RouteLifecycle.initial,
          ),
        ),
      );
    }
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
  }

  @override
  void didUpdateWidget(Navigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observers != widget.observers) {
      for (NavigatorObserver observer in oldWidget.observers) {
        assert(observer.navigator == this);
        observer._navigator = null;
      }
      for (NavigatorObserver observer in widget.observers) {
        assert(observer.navigator == null);
        observer._navigator = this;
      }
    }
    if (oldWidget.pages != widget.pages) {
      _updatePages();
      assert(!_debugLocked);
      assert(() { _debugLocked = true; return true; }());
      _flushHistoryUpdates();
      assert(() { _debugLocked = false; return true; }());
    }
    for (_RouteEntry entry in _history)
      entry.route.changedExternalState();
  }

  @override
  void dispose() {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    for (NavigatorObserver observer in widget.observers)
      observer._navigator = null;
    focusScopeNode.detach();
    for (_RouteEntry entry in _history)
      entry.dispose();
    super.dispose();
    // don't unlock, so that the object becomes unusable
  }

  void _updatePages() {
    int oldIndex = 0;
    int newIndex = 0;
    final List<_RouteEntry> newHistory = <_RouteEntry>[];
    final List<_SkippedRouteEntry> skippedEntries = <_SkippedRouteEntry>[];
    loop: while (true) {
      final _RouteEntry entry = _history[oldIndex];
      // Is the next entry we have yet to look at a page-less route associated with the last paged route?
      if (entry != null && !entry.hasPage) {
        // It is! Copy it into the new history verbatim.
        // Routes without pages at the very start of the history are always kept around.
        newHistory.add(entry);
        oldIndex += 1;
        continue loop;
      }
      assert(entry == null || entry.hasPage);
      // Have we reached the end of the new pages list?
      if (widget.pages.length <= newIndex) {
        break loop; // This is the loop's only exit point.
      }
      final Page<dynamic> page = widget.pages[newIndex];
      assert(page != null);
      // Does this page match a route we skipped earlier in this process?
      for (_SkippedRouteEntry oldEntry in skippedEntries) {
        if (oldEntry.entry.canUpdateFrom(page)) {
          // It does! Copy that route into the new history (with all its subsidiary entries).
          skippedEntries.remove(oldEntry);
          newHistory.add(oldEntry.entry);
          oldEntry.entry.route._updateSettings(page);
          newHistory.addAll(oldEntry.subsidiaryEntries);
          newIndex += 1;
          continue loop;
        }
      }
      assert(!skippedEntries.any((_SkippedRouteEntry oldEntry) => oldEntry.entry.canUpdateFrom(page)));
      // Have we run out of old route entries to examine?
      if (entry == null) {
        // We have. Create a new route from this page.
        final Route<dynamic> newRoute = page.createRoute(context);
        assert(newRoute.settings == page);
        final _RouteEntry newEntry = new _RouteEntry(
          newRoute,
          initialState: _RouteLifecycle.newPage,
        );
        newHistory.add(newEntry);
        continue loop;
      }
      assert(entry != null);
      // We still have old route entries to examine.
      // Does this page match the next entry we have yet to look at in the old history?
      if (entry.canUpdateFrom(page)) {
        // It does! Copy that route into the new history.
        newHistory.add(entry);
        entry.route._updateSettings(page);
        oldIndex += 1;
        newIndex += 1;
        continue loop;
      }
      assert(!entry.canUpdateFrom(page));
      // If we reach here, we have a page that does not match the next entry in
      // the old history. We have to bring that old route, and any of its
      // associated page-less routes, into the skippedEntries list, then try
      // again.
      final _SkippedRouteEntry skippedEntry = new _SkippedRouteEntry(entry: entry, savePoint: newHistory.last);
      skippedEntries.add(skippedEntry);
      oldIndex += 1;
      while (oldIndex < _history.length && !_history[oldIndex].hasPage) {
        skippedEntry.subsidiaryEntries.add(_history[oldIndex]);
        oldIndex += 1;
      }
    } // loop
    // We reach here when the loop above hits the "break loop" line.
    assert(newIndex >= widget.pages.length);
    assert(oldIndex >= _history.length || _history[oldIndex].hasPage);
    // Deal with the popped entries (those that were on the end of the history but are now missing).
    for (int index = _history.length - 1; index >= oldIndex; index -= 1) {
      final _RouteEntry entry = _history[index];
      entry.pop<Null>(null);
      newHistory.add(entry);
    }
    // Deal with the skipped entries.
    final Map<_RouteEntry, List<_RouteEntry>> skippedEntriesBySavePoint = <_RouteEntry, List<_RouteEntry>>{};
    for (_SkippedRouteEntry skippedEntry in skippedEntries) {
      skippedEntry.remove();
      skippedEntriesBySavePoint.putIfAbsent(skippedEntry.savePoint, () => <_RouteEntry>[])
        ..add(skippedEntry.entry)
        ..addAll(skippedEntry.subsidiaryEntries);
    }
    // Now merge the new history with the doomed routes.
    _history.clear();
    if (skippedEntriesBySavePoint.containsKey(null)) {
      // Add entries we skipped at the very start of the list first.
      _history.addAll(skippedEntriesBySavePoint[null]);
    }
    for (_RouteEntry entry in newHistory) {
      // Add each entry in the new list followed by any skipped entries that were associated with it.
      _history.add(entry);
      final List<_RouteEntry> skippedEntries = skippedEntriesBySavePoint[entry];
      if (skippedEntries != null)
        _history.addAll(skippedEntries);
    }
  }

  void _flushHistoryUpdates() {
    assert(_debugLocked);
    // Clean up the list, sending updates to the routes that changed. Notably,
    // we don't send the didChangePrevious/didChangeNext updates to those that
    // did not change at this point, because we're not yet sure exactly what the
    // routes will be at the end of the day (some might get disposed).
    int index = _history.length - 1;
    _RouteEntry next, entry, previous;
    previous = _history[index];
    bool canRemove = false;
    Route<dynamic> poppedRoute; // The route that should trigger didPopNext on the top active route.
    bool seenTopActiveRoute = false; // Whether we've seen the route that would get didPopNext.
    while (index >= 0) {
      next = entry;
      entry = previous;
      previous = index > 0 ? _history[index - 1] : null;
      switch (entry.currentState) {
        case _RouteLifecycle.initial:
        case _RouteLifecycle.push:
        case _RouteLifecycle.replace:
          entry.handleAddition(navigator: this, previous: previous, next: next);
          assert(entry.currentState != _RouteLifecycle.initial);
          assert(entry.currentState != _RouteLifecycle.push);
          assert(entry.currentState != _RouteLifecycle.replace);
          break;
        case _RouteLifecycle.pushing:
          // Will exit this state when animation completes.
          if (!seenTopActiveRoute && poppedRoute != null)
            entry.route.didPopNext(poppedRoute);
          seenTopActiveRoute = true;
          break;
        case _RouteLifecycle.idle:
          if (!seenTopActiveRoute && poppedRoute != null)
            entry.route.didPopNext(poppedRoute);
          seenTopActiveRoute = true;
          // This route is idle, so we are allowed to remove subsequent (earlier)
          // routes that are waiting to be removed silently:
          canRemove = true;
          break;
        case _RouteLifecycle.pop:
          if (!seenTopActiveRoute) {
            if (poppedRoute != null)
              entry.route.didPopNext(poppedRoute);
            poppedRoute = entry.route;
          }
          entry.handlePop(navigator: this);
          assert(entry.currentState == _RouteLifecycle.popping);
          break;
        case _RouteLifecycle.popping:
          // Will exit this state when animation completes.
          break;
        case _RouteLifecycle.remove:
          if (!seenTopActiveRoute) {
            if (poppedRoute != null)
              entry.route.didPopNext(poppedRoute);
            poppedRoute = null;
          }
          entry.handleRemoval(navigator: this);
          assert(entry.currentState == _RouteLifecycle.removing);
          continue;
        case _RouteLifecycle.removing:
          if (!canRemove && next != null) {
            // We aren't allowed to remove this route yet.
            break;
          }
          entry.currentState = _RouteLifecycle.dispose;
          continue;
        case _RouteLifecycle.dispose:
          entry.dispose();
          _history.removeAt(index);
          entry = next;
          break;
        case _RouteLifecycle.disposed:
          assert(false);
          break;
      }
      index -= 1;
    }
    // Now that the list is clean, send the didChangeNext/didChangePrevious
    // notifications.
    index = _history.length - 1;
    entry = null;
    previous = _history[index];
    while (index >= 0) {
      next = entry;
      entry = previous;
      previous = index > 0 ? _history[index - 1] : null;
      if (next != entry.lastAnnouncedNextRoute) {
        entry.route.didChangeNext(next);
        entry.lastAnnouncedNextRoute = next;
      }
      if (previous != entry.lastAnnouncedPreviousRoute) {
        entry.route.didChangePrevious(previous);
        entry.lastAnnouncedPreviousRoute = previous;
      }
      index -= 1;
    }
    overlay?.rearrange(_allRouteOverlayEntries);
  }

  Route<T> _routeNamed<T>(String name, { @required TypedDictionary arguments, bool allowNull = false }) {
    assert(!_debugLocked);
    assert(name != null);
    assert(arguments != null);
    if (allowNull && widget.onGenerateRoute == null)
      return null;
    assert(() {
      if (widget.onGenerateRoute == null) {
        throw new FlutterError(
          'Navigator.onGenerateRoute was null, but the route named "$name" was referenced.\n'
          'To use the Navigator API with named routes (pushNamed, pushReplacementNamed, or '
          'pushNamedAndRemoveUntil), the Navigator must be provided with an '
          'onGenerateRoute handler.\n'
          'The Navigator was:\n'
          '  $this'
        );
      }
      return true;
    }());
    final RouteSettings settings = new RouteSettings(
      name: name,
      arguments: arguments,
    );
    Route<T> route = widget.onGenerateRoute(settings);
    assert(() {
      if (route == null && widget.onUnknownRoute == null && !allowNull) {
        throw new FlutterError(
          'Navigator.onGenerateRoute returned null when requested to build route "$name".\n'
          'The onGenerateRoute callback must never return null, unless an onUnknownRoute '
          'callback is provided as well.\n'
          'The Navigator was:\n'
          '  $this'
        );
      }
      return true;
    }());
    if (route == null && widget.onUnknownRoute != null) {
      route = widget.onUnknownRoute(settings);
      assert(() {
        if (route == null) {
          throw new FlutterError(
            'Navigator.onUnknownRoute returned null when requested to build route "$name".\n'
            'The onUnknownRoute callback must never return null.\n'
            'The Navigator was:\n'
            '  $this'
          );
        }
        return true;
      }());
    }
    assert(route != null || allowNull);
    return route;
  }

  /// Push a named route onto the navigator.
  ///
  /// {@macro flutter.widgets.navigator.pushNamed}
  ///
  /// To use [pushNamed], a [Navigator.onGenerateRoute] must be provided, either
  /// directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _aaronBurrSir() {
  ///   navigator.pushNamed('/nyc/1776');
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> pushNamed<T extends Object>(
    String routeName, {
    TypedDictionary arguments: TypedDictionary.empty,
  }) {
    return push<T>(_routeNamed<T>(routeName, arguments: arguments));
  }

  /// Replace the current route of the navigator by pushing the route named
  /// [routeName] and then disposing the previous route once the new route has
  /// finished animating in.
  ///
  /// {@macro flutter.widgets.navigator.pushReplacementNamed}
  ///
  /// To use [pushReplacementNamed], a [Navigator.onGenerateRoute] must be
  /// provided, either directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _startBike() {
  ///   navigator.pushReplacementNamed('/jouett/1781');
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> pushReplacementNamed<T extends Object, TO extends Object>(String routeName, {
    TO result,
    TypedDictionary arguments: TypedDictionary.empty,
  }) {
    return pushReplacement<T, TO>(_routeNamed<T>(routeName, arguments: arguments), result: result);
  }

  /// Pop the current route off the navigator and push a named route in its
  /// place.
  ///
  /// {@macro flutter.widgets.navigator.popAndPushNamed}
  ///
  /// To use [popAndPushNamed], a [Navigator.onGenerateRoute] must be provided,
  /// either directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _begin() {
  ///   navigator.popAndPushNamed('/nyc/1776');
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> popAndPushNamed<T extends Object, TO extends Object>(
    String routeName, {
    TO result,
    TypedDictionary arguments: TypedDictionary.empty,
  }) {
    pop<TO>(result);
    return pushNamed<T>(routeName, arguments: arguments);
  }

  /// Push the route with the given name onto the navigator, and then remove all
  /// the previous routes until the `predicate` returns true.
  ///
  /// {@macro flutter.widgets.navigator.pushNamedAndRemoveUntil}
  ///
  /// To use [pushNamedAndRemoveUntil], a [Navigator.onGenerateRoute] must be
  /// provided, either directly or via a specially-configured [Router]. See
  /// [DefaultRouteNameProvider] for details.
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _handleOpenCalendar() {
  ///   navigator.pushNamedAndRemoveUntil('/calendar', ModalRoute.withName('/'));
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> pushNamedAndRemoveUntil<T extends Object>(
    String newRouteName,
    RoutePredicate predicate, {
    TypedDictionary arguments: TypedDictionary.empty,
  }) {
    return pushAndRemoveUntil<T>(_routeNamed<T>(newRouteName, arguments: arguments), predicate);
  }

  /// Push the given route onto the navigator.
  ///
  /// {@macro flutter.widgets.navigator.push}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _openPage() {
  ///   navigator.push(new MaterialPageRoute(builder: (BuildContext context) => new MyScreen()));
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> push<T extends Object>(Route<T> route) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(route != null);
    assert(route._navigator == null);
    _history.add(new _RouteEntry(route, initialState: _RouteLifecycle.push));
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
    _cancelActivePointers();
    return route.popped;
  }

  /// Replace the current route of the navigator by pushing the given route and
  /// then disposing the previous route once the new route has finished
  /// animating in.
  ///
  /// {@macro flutter.widgets.navigator.pushReplacement}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _doOpenPage() {
  ///   navigator.pushReplacement(
  ///       new MaterialPageRoute(builder: (BuildContext context) => new MyHomePage()));
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> pushReplacement<T extends Object, TO extends Object>(Route<T> newRoute, { TO result }) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(newRoute != null);
    assert(newRoute._navigator == null);
    assert(_history.isNotEmpty);
    assert(_history.contains(_RouteEntry.isPresentPredicate), 'Navigator has no active routes to replace.');
    _history.lastWhere(_RouteEntry.isPresentPredicate).remove<TO>(result);
    _history.add(new _RouteEntry(newRoute, initialState: _RouteLifecycle.replace));
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
    _cancelActivePointers();
    return newRoute.popped;
  }

  /// Push the given route onto the navigator, and then remove all the previous
  /// routes until the `predicate` returns true.
  ///
  /// {@macro flutter.widgets.navigator.pushAndRemoveUntil}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _resetAndOpenPage() {
  ///   navigator.pushAndRemoveUntil(
  ///     new MaterialPageRoute(builder: (BuildContext context) => new MyHomePage()),
  ///     ModalRoute.withName('/'),
  ///   );
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> pushAndRemoveUntil<T extends Object>(Route<T> newRoute, RoutePredicate predicate) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(newRoute != null);
    assert(newRoute._navigator == null);
    assert(predicate != null);
    int index = _history.length - 1;
    _history.add(new _RouteEntry(newRoute, initialState: _RouteLifecycle.push));
    while (index >= 0) {
      final _RouteEntry entry = _history[index];
      if (entry.isPresent && !predicate(entry.route))
        _history[index].remove<Null>();
      index -= 1;
    }
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
    _cancelActivePointers();
    return newRoute.popped;
  }

  /// Replaces a route on the navigator with a new route.
  ///
  /// {@macro flutter.widgets.navigator.replace}
  ///
  /// See also:
  ///
  ///  * [replaceRouteBelow], which is the same but identifies the route to be
  ///    removed by reference to the route above it, rather than directly.
  @optionalTypeArgs
  void replace<T extends Object>({ @required Route<dynamic> oldRoute, @required Route<T> newRoute }) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(oldRoute != null);
    assert(oldRoute._navigator == this);
    assert(newRoute != null);
    assert(newRoute._navigator == null);
    final int index = _history.indexWhere(_RouteEntry.isRoutePredicate(oldRoute));
    assert(index >= 0, 'This Navigator does not contain the specified oldRoute.');
    assert(_history[index].isPresent, 'The specified oldRoute has already been removed from the Navigator.');
    final bool wasCurrent = oldRoute.isCurrent;
    _history.insert(index + 1, newRoute, initialState: _RouteLifecycle.replace);
    _history[index].remove<Null>();
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
    if (wasCurrent)
      _cancelActivePointers();
  }

  /// Replaces a route on the navigator with a new route. The route to be
  /// replaced is the one below the given `anchorRoute`.
  ///
  /// {@macro flutter.widgets.navigator.replaceRouteBelow}
  ///
  /// See also:
  ///
  ///  * [replace], which is the same but identifies the route to be removed
  ///    directly.
  @optionalTypeArgs
  void replaceRouteBelow<T extends Object>({ @required Route<dynamic> anchorRoute, Route<T> newRoute }) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(anchorRoute != null);
    assert(anchorRoute._navigator == this);
    assert(newRoute != null);
    assert(newRoute._navigator == null);
    final int anchorIndex = _history.indexWhere(_RouteEntry.isRoutePredicate(anchorRoute));
    assert(anchorIndex >= 0, 'This Navigator does not contain the specified anchorRoute.');
    assert(_history[anchorIndex].isPresent, 'The specified anchorRoute has already been removed from the Navigator.');
    int index = anchorIndex - 1;
    while (index >= 0) {
      if (_history[index].isPresent)
        break;
      index -= 1;
    }
    assert(index >= 0, 'There are no routes below the specified anchorRoute.');
    _history.insert(index + 1, newRoute, initialState: _RouteLifecycle.replace);
    _history[index].remove<Null>();
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
  }

  /// Whether the navigator can be popped.
  ///
  /// {@macro flutter.widgets.navigator.canPop}
  ///
  /// See also:
  ///
  ///  * [Route.isFirst], which returns true for routes for which [canPop]
  ///    returns false.
  bool canPop() {
    Iterator<_RouteEntry> iterator = _history.where(_RouteEntry.isPresentPredicate).iterator;
    if (!iterator.moveNext())
      return false; // we have no active routes, so we can't pop
    if (iterator.current.route.willHandlePopInternally)
      return true; // the first route can handle pops itself, so we can pop
    if (!iterator.moveNext())
      return false; // there's only one route, so we can't pop
    return true; // there's at least two routes, so we can pop
  }

  /// Consults the current route's [Route.willPop] method, and acts accordingly,
  /// potentially popping the route as a result; returns whether the pop request
  /// should be considered handled.
  ///
  /// {@macro flutter.widgets.navigator.maybePop}
  ///
  /// See also:
  ///
  /// * [Form], which provides an `onWillPop` callback that enables the form
  ///   to veto a [pop] initiated by the app's back button.
  /// * [ModalRoute], which provides a `scopedWillPopCallback` that can be used
  ///   to define the route's `willPop` method.
  @optionalTypeArgs
  Future<bool> maybePop<T extends Object>([ T result ]) async {
    final _RouteEntry lastEntry = _history.lastWhere(_RouteEntry.isPresentPredicate, orElse: () => null);
    if (lastEntry == null)
      return false;
    assert(lastEntry.route._navigator == this);
    final RoutePopDisposition disposition = await lastEntry.route.willPop(); // this is asynchronous
    assert(disposition != null);
    if (!mounted)
      return true; // forget about this pop, we were disposed in the meantime
    final _RouteEntry newLastEntry = _history.lastWhere(_RouteEntry.isPresentPredicate, orElse: () => null);
    if (lastEntry != newLastEntry)
      return true; // forget about this pop, something happened to our history in the meantime
    switch (disposition) {
      case RoutePopDisposition.bubble:
        return false;
      case RoutePopDisposition.pop:
        pop(result);
        return true;
      case RoutePopDisposition.doNotPop:
        return true;
    }
    return null;
  }

  /// Pop the top-most route off the navigator.
  ///
  /// {@macro flutter.widgets.navigator.pop}
  ///
  /// ## Sample code
  ///
  /// Typical usage for closing a route is as follows:
  ///
  /// ```dart
  /// void _handleClose() {
  ///   navigator.pop();
  /// }
  /// ```
  ///
  /// A dialog box might be closed with a result:
  ///
  /// ```dart
  /// void _handleAccept() {
  ///   navigator.pop(true); // dialog returns true
  /// }
  /// ```
  @optionalTypeArgs
  void pop<T extends Object>([ T result ]) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    final _RouteEntry entry = _history.lastWhere(_RouteEntry.isPresentPredicate);
    if (entry.hasPage) {
      assert(
        widget.onPopPage,
        'Navigator.pop was called for a Page (specified in Navigator.pages), '
        'but no Navigator.onPopPage handler was provided.',
      );
      if (widget.onPopPage != null && !widget.onPopPage(entry.route, result)) {
        assert(
          entry.route._popCompleter.isComplete,
          'The Navigator.onPopPage handler must call Route.didPop or '
          'Route.didComplete on the route it is popping.',
        );
        entry.markPopped();
        _flushHistoryUpdates();
      }
    } else {
      if (!entry.pop<T>(result))
        _flushHistoryUpdates();
      assert(entry.route._popCompleter.isComplete);
    }
    assert(() { _debugLocked = false; return true; }());
    _cancelActivePointers();
  }

  /// Calls [pop] repeatedly until the predicate returns true.
  ///
  /// {@macro flutter.widgets.navigator.popUntil}
  ///
  /// ## Sample code
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// void _doLogout() {
  ///   navigator.popUntil(ModalRoute.withName('/login'));
  /// }
  /// ```
  void popUntil(RoutePredicate predicate) {
    for (int index = _history.length - 1; index >= 0; index -= 1) {
      if (_history[index].isPresent) {
        if (predicate(_history.last))
          break;
        pop();
      }
    }
  }

  /// Immediately remove `route` from the navigator, and [Route.dispose] it.
  ///
  /// {@macro flutter.widgets.navigator.removeRoute}
  void removeRoute(Route<dynamic> route) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(route != null);
    assert(route._navigator == this);
    final bool wasCurrent = route.isCurrent;
    final _RouteEntry entry = _history.firstWhere(_RouteEntry.isRoutePredicate(route), orElse: () => null);
    assert(entry != null);
    entry.remove<Null>();
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
    if (wasCurrent)
      _cancelActivePointers();
  }

  /// Immediately remove a route from the navigator, and [Route.dispose] it. The
  /// route to be replaced is the one below the given `anchorRoute`.
  ///
  /// {@macro flutter.widgets.navigator.removeRouteBelow}
  void removeRouteBelow(Route<dynamic> anchorRoute) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(anchorRoute != null);
    assert(anchorRoute._navigator == this);
    final int anchorIndex = _history.indexWhere(_RouteEntry.isRoutePredicate(anchorRoute));
    assert(anchorIndex >= 0, 'This Navigator does not contain the specified anchorRoute.');
    assert(_history[anchorIndex].isPresent, 'The specified anchorRoute has already been removed from the Navigator.');
    int index = anchorIndex - 1;
    while (index >= 0) {
      if (_history[index].isPresent)
        break;
      index -= 1;
    }
    assert(index >= 0, 'There are no routes below the specified anchorRoute.');
    _history[index].remove<Null>();
    _flushHistoryUpdates();
    assert(() { _debugLocked = false; return true; }());
  }

  /// Complete the lifecycle for a route that has been popped off the navigator.
  ///
  /// When the navigator pops a route, the navigator retains a reference to the
  /// route in order to call [Route.dispose] if the navigator itself is removed
  /// from the tree. When the route is finished with any exit animation, the
  /// route should call this function to complete its lifecycle (e.g., to
  /// receive a call to [Route.dispose]).
  ///
  /// The given `route` must have already received a call to [Route.didPop].
  /// This function may be called directly from [Route.didPop] if [Route.didPop]
  /// will return true.
  void finalizeRoute(Route<dynamic> route) {
    assert(_history.where(_RouteEntry.isRoutePredicate(route)).length == 1);
    _history.firstWhere(_RouteEntry.isRoutePredicate(route)).finalize();
    _flushHistoryUpdates();
  }

  /// Whether a route is currently being manipulated by the user, e.g.
  /// as during an iOS back gesture.
  bool get userGestureInProgress => _userGesturesInProgress > 0;
  int _userGesturesInProgress = 0;

  /// The navigator is being controlled by a user gesture.
  ///
  /// For example, called when the user beings an iOS back gesture.
  ///
  /// When the gesture finishes, call [didStopUserGesture].
  void didStartUserGesture() {
    _userGesturesInProgress += 1;
    if (_userGesturesInProgress == 1) {
      for (NavigatorObserver observer in widget.observers)
        observer.didStartUserGesture();
    }
  }

  /// A user gesture completed.
  ///
  /// Notifies the navigator that a gesture regarding which the navigator was
  /// previously notified with [didStartUserGesture] has completed.
  void didStopUserGesture() {
    assert(_userGesturesInProgress > 0);
    _userGesturesInProgress -= 1;
    if (_userGesturesInProgress == 0) {
      for (NavigatorObserver observer in widget.observers)
        observer.didStopUserGesture();
    }
  }

  final Set<int> _activePointers = new Set<int>();

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
  }

  void _cancelActivePointers() {
    // TODO(abarth): This mechanism is far from perfect. See https://github.com/flutter/flutter/issues/4770
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      // If we're between frames (SchedulerPhase.idle) then absorb any
      // subsequent pointers from this frame. The absorbing flag will be
      // reset in the next frame, see build().
      final RenderAbsorbPointer absorber = _overlayKey.currentContext?.ancestorRenderObjectOfType(const TypeMatcher<RenderAbsorbPointer>());
      setState(() {
        absorber?.absorbing = true;
        // We do this in setState so that we'll reset the absorbing value back
        // to false on the next frame.
      });
    }
    _activePointers.toList().forEach(WidgetsBinding.instance.cancelPointer);
  }

  @override
  Widget build(BuildContext context) {
    assert(!_debugLocked);
    assert(_history.isNotEmpty);
    return new Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUpOrCancel,
      onPointerCancel: _handlePointerUpOrCancel,
      child: new AbsorbPointer(
        absorbing: false, // it's mutated directly by _cancelActivePointers above
        child: new FocusScope(
          node: focusScopeNode,
          autofocus: true,
          child: new Overlay(
            key: _overlayKey,
            initialEntries: overlay == null ? _allRouteOverlayEntries : null,
          ),
        ),
      ),
    );
  }
}
