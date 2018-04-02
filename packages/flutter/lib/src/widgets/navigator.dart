// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

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
// class MyPage extends Placeholder { MyPage({String title}); }
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
typedef List<Route<dynamic>> RouteListFactory();

/// Signature for the [Navigator.popUntil] predicate argument.
typedef bool RoutePredicate(Route<dynamic> route);

/// Signature for a callback that verifies that it's OK to call [Navigator.pop].
///
/// Used by [Form.onWillPop], [ModalRoute.addScopedWillPopCallback],
/// [ModalRoute.removeScopedWillPopCallback], and [WillPopScope].
typedef Future<bool> WillPopCallback();

typedef bool PagePopCallback(dynamic result);

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
    this.arguments: TypedDictionary.empty,
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
abstract class Page<T> extends RouteSettings {
  /// Initializes [key] for subclasses.
  ///
  /// The [arguments] argument must not be null.
  const Page({
    this.key,
    String name,
    TypedDictionary arguments: TypedDictionary.empty,
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
abstract class Route<T> {
  /// Initialize the [Route].
  ///
  /// If the [settings] are not provided, an empty [RouteSettings] object is
  /// used instead. If this [Route] was created from a [Page] in a [Navigator.pages] list (via
  /// [Page.createRoute]), then the [settings] argument must be set to that [Page].
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

  void _updateRouteSettings(RouteSettings newSettings) {
    assert(newSettings != null);
    if (_settings != newSettings) {
      _settings = newSettings;
      changedInternalState();
    }
  }

  /// The overlay entries for this route.
  List<OverlayEntry> get overlayEntries => const <OverlayEntry>[];

  /// Called when the route is inserted into the navigator.
  ///
  /// Use this to populate [overlayEntries] and add them to the overlay
  /// (accessible as [Navigator.overlay]). (The reason the [Route] is
  /// responsible for doing this, rather than the [Navigator], is that the
  /// [Route] will be responsible for _removing_ the entries and this way it's
  /// symmetric.)
  ///
  /// The `insertionPoint` argument will be null if this is the first route
  /// inserted. Otherwise, it indicates the overlay entry to place immediately
  /// below the first overlay for this route.
  ///
  /// The `isInitialRoute` argument indicates whether this route is part of the
  /// first batch of routes being pushed onto the [Navigator]. Typically this
  /// is used to skip any entrance transition during startup.
  @protected
  @mustCallSuper
  void install(OverlayEntry insertionPoint, { bool isInitialRoute: false }) { }

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
  void didReplace(Route<dynamic> oldRoute) { }

  /// Returns false if this route wants to veto a [Navigator.pop]. This method is
  /// called by [Navigator.maybePop].
  ///
  /// By default, routes veto a pop if they're the first route in the history
  /// (i.e., if [isFirst]). This behavior prevents the user from popping the
  /// first route off the history and being stranded at a blank screen.
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
  T get currentResult => null;

  /// A future that completes when this route is popped off the navigator.
  ///
  /// The future completes with the value given to [Navigator.pop], if any.
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
  @protected
  @mustCallSuper
  bool didPop(T result) {
    didComplete(result);
    return true;
  }

  /// The route was popped or is otherwise being removed somewhat gracefully.
  ///
  /// This is called by [didPop] and in response to
  /// [NavigatorState.pushReplacement].
  ///
  /// The [popped] future is completed by this method.
  @protected
  @mustCallSuper
  void didComplete(T result) {
    _popCompleter.complete(result);
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

  /// The route should remove its overlays and free any other resources.
  ///
  /// This route is no longer referenced by the navigator.
  @mustCallSuper
  @protected
  void dispose() {
    _navigator = null;
  }

  /// Whether this route is the top-most route on the navigator.
  ///
  /// If this is true, then [isActive] is also true.
  bool get isCurrent {
    return _navigator != null && _navigator._history.last == this;
  }

  /// Whether this route is the bottom-most route on the navigator.
  ///
  /// If this is true, then [Navigator.canPop] will return false if this route's
  /// [willHandlePopInternally] returns false.
  ///
  /// If [isFirst] and [isCurrent] are both true then this is the only route on
  /// the navigator (and [isActive] will also be true).
  bool get isFirst {
    return _navigator != null && _navigator._history.first == this;
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
    return _navigator != null && _navigator._history.contains(this);
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
/// way analogous to how a [Widget] represents a potential [Element].
///
/// The [pages] property works in terms of [Page] objects, while the [Navigator
/// API] (the static methods on [Navigator] and the identically-named methods on
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
///       '/a': (BuildContext context) => new MyPage(title: 'page A'),
///       '/b': (BuildContext context) => new MyPage(title: 'page B'),
///       '/c': (BuildContext context) => new MyPage(title: 'page C'),
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
/// If it is non-null, the [onGenerateInitialRoutes] method will be called to
/// determine routes to insert into the [Navigator] when it is created.
///
/// ## Nesting Navigators
///
/// An app can use more than one [Navigator]. Nesting one [Navigator] below
/// another [Navigator] can be used to create an "inner journey" such as tabbed
/// navigation, user registration, store checkout, or other independent journeys
/// that represent a subsection of your overall application.
///
/// ### Real world example
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
    this.pages = const <Page>[],
    this.onPopPage,
    this.onGenerateInitialRoutes,
    this.onGenerateRoute,
    this.transitionDelegate = const DefaultNavigatorTransitionDelegate(),
    this.observers = const <NavigatorObserver>[],
  }) : super(key: key);

  /// The list of pages with which to populate the history.
  ///
  /// Pages are turned into routes using [Page.createRoute] in a manner
  /// analogous to how [Widget]s are turned into [Element]s (and [State]s or
  /// [RenderObject]s) using [Widget.createElement] (and
  /// [StatefulWidget.createState] or [RenderObjectWidget.createRenderObject).
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
  final List<Page> pages;

  /// Called when [pop] is invoked but the current [Route] corresponds to a
  /// [Page] found in the [pages] list.
  ///
  /// The [Navigator] widget should be rebuilt with a [pages] list that does not
  /// contain the given [Page].
  final PagePopCallback onPopPage;

  /// Called to generate a route for a given [RouteSettings] that isn't a [Page].
  ///
  /// This is used by [pushNamed] and friends, i.e. for routes that do not
  /// correspond to a [Page] object in [pages]. They create a [RouteSettings]
  /// object based on their arguments, call this method to generate the
  /// corresponding [Route], and then use [push] and friends to actually update
  /// the navigator's history.
  ///
  /// If this is null, then [pushNamed] and friends will fail. This is common in
  /// applications that use a [Router] with a custom [ParsedRouteHandler]
  /// instead of using the [DefaultParsedRouteHandler], a route table, and
  /// [pushNamed].
  final RouteFactory onGenerateRoute;

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
    TypedDictionary arguments: TypedDictionary.empty,
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
    TypedDictionary arguments: TypedDictionary.empty,
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
    TypedDictionary arguments: TypedDictionary.empty,
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
    TypedDictionary arguments: TypedDictionary.empty,
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
  /// void _openMyPage() {
  ///   Navigator.push(context, new MaterialPageRoute(builder: (BuildContext context) => new MyPage()));
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

  /// Returns the value of the current route's [Route.willPop] method for the
  /// navigator that most tightly encloses the given context.
  ///
  /// {@template flutter.widgets.navigator.maybePop}
  /// This method is typically called before a user-initiated [pop]. For example
  /// on Android it's called by the binding for the system's back button.
  ///
  /// The `T` type argument is the type of the return value of the current
  /// route.
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
  /// If the route in question was added using [Navigator.pages], the
  /// [Navigator.onPopPage] callback is invoked, passing it the `result`
  /// argument.
  ///
  /// Otherwise, the current route's [Route.didPop] method is called; if that
  /// method returns false, then this method returns true but nothing else is
  /// changed (the route is expected to have popped some internal state; see
  /// e.g. [LocalHistoryRoute]).
  ///
  /// Otherwise, if non-null, `result` will be used as the result of the route
  /// that is popped; the future that had been returned from pushing the popped
  /// route will complete with `result`. Routes such as dialogs or popup menus
  /// typically use this mechanism to return the value selected by the user to
  /// the widget that created their route. The type of `result`, if provided,
  /// must match the type argument of the class of the popped route (`T`).
  ///
  /// The popped route and the route below it are notified (see [Route.didPop],
  /// [Route.didComplete], and [Route.didPopNext]). If the [Navigator] has any
  /// [Navigator.observers], they will be notified as well (see
  /// [NavigatorObserver.didPop]).
  ///
  /// The `T` type argument is the type of the return value of the popped route.
  ///
  /// Returns true if a route was popped (including if [Route.didPop] returned
  /// false); returns false if there are no further previous routes.
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
  static bool pop<T extends Object>(BuildContext context, [ T result ]) {
    return Navigator.of(context).pop<T>(result);
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
t  }

  @override
  NavigatorState createState() => new NavigatorState();
}

enum _RouteLifecycle {
  push, // we'll want to run install, didPush, etc
  replace, // we'll want to run install, didReplace, etc
  idle, // route is being harmless
  popping, // we have called didPop, we're waiting for the future to complete, then will remove
  removing, // we are waiting for subsequent routes to be done pushing, then will remove
  remove, // we'll want to run didReplace/didRemove etc
}

class _RouteEntry {
  _RouteEntry(
    this.route, {
    _RouteLifecycle initialState,
  }) : assert(route != null),
       assert(initialState != null),
       assert(initialState == _RouteLifecycle.push || initialState == _RouteLifecycle.replace),
       currentState = initialState;

  final Route<dynamic> route;
  final Route<dynamic> lastAnnouncedNextRoute;
  final Route<dynamic> lastAnnouncedPreviousRoute;

  bool get hasPage => route.settings is Page;

  _RouteLifecycle currentState;

  void pop<T>(T result) {
    // xxx
  }

  void remove<T>(T result) {
    // xxx
  }
}

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
    // xxx
  }
}

class NavigatorTransitionDelegate {
  // xxx
}

class DefaultNavigatorTransitionDelegate extends NavigatorTransitionDelegate {
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

  @override
  void initState() {
    super.initState();
    for (NavigatorObserver observer in widget.observers) {
      assert(observer.navigator == null);
      observer._navigator = this;
    }
    _updatePages();
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
    if (oldWidget.pages != widget.pages)
      _updatePages();
    for (RouteEntry<dynamic> entry in _history)
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
      entry.route.dispose();
    super.dispose();
    // don't unlock, so that the object becomes unusable
  }

  OverlayEntry get _currentOverlayEntry {
    for (Route<dynamic> route in _history.reversed) {
      if (route.overlayEntries.isNotEmpty)
        return route.overlayEntries.last;
    }
    return null;
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
        break loop;
      }
      final Page page = widget.pages[newIndex];
      assert(page != null);
      // Does this page match a route we skipped earlier in this process?
      for (_SkippedRouteEntry oldEntry in skippedEntries) {
        if (oldEntry.entry.route.page.canUpdate(page)) {
          // It does! Copy that route into the new history (with all its subsidiary entries).
          skippedEntries.remove(oldEntry);
          newHistory.add(oldEntry.entry);
          oldEntry.entry.route._updateSettings(page);
          newHistory.addAll(oldEntry.subsidiaryEntries);
          newIndex += 1;
          continue loop;
        }
      }
      assert(!skippedEntries.any((_SkippedRouteEntry oldEntry) => oldEntry.entry.route.page.canUpdate(page)));
      // Have we run out of old route entries to examine?
      if (entry == null) {
        // We have. Create a new route from this page.
        final Route newRoute = page.createRoute(context);
        final _RouteEntry newEntry = new _RouteEntry(newRoute);
        newHistory.add(newEntry);
        continue loop;
      }
      assert(entry != null);
      // We still have old route entries to examine.
      // Does this page match the next entry we have yet to look at in the old history?
      if (entry.route.page.canUpdate(page)) {
        // It does! Copy that route into the new history.
        newHistory.add(entry);
        entry.route._updatePage(page);
        oldIndex += 1;
        newIndex += 1;
        continue loop;
      }
      assert(!entry.route.page.canUpdate(page));
      // If we reach here, we have a page that does not match the next entry in
      // the old history. We have to bring that old route, and any of its
      // associated page-less routes, into the skippedEntries list, then try
      // again.
      final _SkippedRouteEntry skippedEntry = new _SkippedRouteEntry(entry, newHistory.last);
      skippedEntries.add(entrskippedEntry);
      oldIndex += 1;
      while (oldIndex < _history.length && !_history[oldIndex].hasPage) {
        skippedEntries.subsidiaryEntries.add(_history[oldIndex]);
        oldIndex += 1;
      }
    }
    assert(newIndex >= widget.pages.length);
    assert(oldIndex >= _history.length || _history[oldIndex].hasPage);
    // Deal with the popped entries (those that were on the end of the history but are now missing).
    for (int index = _history.length - 1; index >= oldIndex; index -= 1) {
      final _RouteEntry entry = _history[index];
      entry.pop();
      newHistory.add(entry);
    }
    // Deal with the skipped entries.
    Map<_RouteEntry, List<_RouteEntry>> skippedEntriesBySavePoint = <_RouteEntry, List<_RouteEntry>>{};
    for (_SkippedRouteEntry skippedEntry in skippedEntries) {
      entry.remove();
      skippedEntriesBySavePoint.putIfAbsent(entry.savePoint, () => <_RouteEntry>[])
        ..add(skippedEntry.entry)
        ..addAll(skippedEntry.subsidiaryEntries);
    }
    _flushHistoryUpdates();
  }

  void _flushHistoryUpdates() {
    // xxx handle updated lifecycles
    // xxx send out notifications, etc
    // (this should be done in a separate function so we can reuse it from push() et al)

    // PUSH/INSTALL
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    final Route<dynamic> oldRoute = _history.isNotEmpty ? _history.last : null;
    route._navigator = this;
    route.install(_currentOverlayEntry);
    _history.add(route);
    route.didPush();
    route.didChangeNext(null);
    if (oldRoute != null)
      oldRoute.didChangeNext(route);
    for (NavigatorObserver observer in widget.observers)
      observer.didPush(route, oldRoute);
    // xxxx

    // PUSH REPLACE
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    final Route<dynamic> oldRoute = _history.last;
    assert(oldRoute != null && oldRoute._navigator == this);
    assert(oldRoute.overlayEntries.isNotEmpty);
    assert(newRoute._navigator == null);
    assert(newRoute.overlayEntries.isEmpty);
    final int index = _history.length - 1;
    assert(index >= 0);
    assert(_history.indexOf(oldRoute) == index);
    newRoute._navigator = this;
    newRoute.install(_currentOverlayEntry);
    _history[index] = newRoute;
    newRoute.didPush().whenCompleteOrCancel(() {
      // The old route's exit is not animated. We're assuming that the
      // new route completely obscures the old one.
      if (mounted) {
        oldRoute
          ..didComplete(result ?? oldRoute.currentResult)
          ..dispose();
      }
    });
    newRoute.didChangeNext(null);
    if (index > 0)
      _history[index - 1].didChangeNext(newRoute);
    for (NavigatorObserver observer in widget.observers)
      observer.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    // xxxx

    // PUSH REMOVE UNTIL
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    final List<Route<dynamic>> removedRoutes = <Route<dynamic>>[];
    while (_history.isNotEmpty && !predicate(_history.last)) {
      final Route<dynamic> removedRoute = _history.removeLast();
      assert(removedRoute != null && removedRoute._navigator == this);
      assert(removedRoute.overlayEntries.isNotEmpty);
      removedRoutes.add(removedRoute);
    }
    assert(newRoute._navigator == null);
    assert(newRoute.overlayEntries.isEmpty);
    final Route<dynamic> oldRoute = _history.isNotEmpty ? _history.last : null;
    newRoute._navigator = this;
    newRoute.install(_currentOverlayEntry);
    _history.add(newRoute);
    newRoute.didPush().whenCompleteOrCancel(() {
      if (mounted) {
        for (Route<dynamic> route in removedRoutes)
          route.dispose();
      }
    });
    newRoute.didChangeNext(null);
    if (oldRoute != null)
      oldRoute.didChangeNext(newRoute);
    for (NavigatorObserver observer in widget.observers) {
      observer.didPush(newRoute, oldRoute);
      for (Route<dynamic> removedRoute in removedRoutes)
        observer.didRemove(removedRoute, oldRoute);
    }
    // xxxx
  }

  Route<T> _routeNamed<T>(String name, { @required TypedDictionary arguments }) {
    assert(!_debugLocked);
    assert(name != null);
    assert(arguments != null);
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
    final Route<T> route = widget.onGenerateRoute(settings);
    assert(() {
      if (route == null) {
        throw new FlutterError(
          'Navigator.onGenerateRoute returned null when requested to build route "$name".\n'
          'The onGenerateRoute callback must never return null.\n'
          'The Navigator was:\n'
          '  $this'
        );
      }
      return true;
    }());
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
  ///   navigator.push(new MaterialPageRoute(builder: (BuildContext context) => new MyPage()));
  /// }
  /// ```
  @optionalTypeArgs
  Future<T> push<T extends Object>(Route<T> route) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    assert(route != null);
    assert(route._navigator == null);
    _history.add(new _RouteEntry(route));
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
    assert(_history.isNotEmpty);
    _history.last.remove<TO>(result);
    _history.add(new _RouteEntry(route));
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
    int index = _history.length - 1;
    _history.add(new _RouteEntry(newRoute));
    while (index >= 0 && !predicate(_history[index].route)) {
      _history[index].remove();
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
    assert(oldRoute != null);
    assert(newRoute != null);
    if (oldRoute == newRoute) // ignore: unrelated_type_equality_checks, https://github.com/dart-lang/sdk/issues/32522
      return;
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    assert(() { _debugLocked = true; return true; }());
    assert(oldRoute._navigator == this);
    assert(newRoute._navigator == null);
    assert(oldRoute.overlayEntries.isNotEmpty);
    assert(newRoute.overlayEntries.isEmpty);
    assert(!overlay.debugIsVisible(oldRoute.overlayEntries.last));
    final int index = _history.indexOf(oldRoute);
    assert(index >= 0);
    newRoute._navigator = this;
    newRoute.install(oldRoute.overlayEntries.last);
    _history[index] = newRoute;
    newRoute.didReplace(oldRoute);
    if (index + 1 < _history.length) {
      newRoute.didChangeNext(_history[index + 1]);
      _history[index + 1].didChangePrevious(newRoute);
    } else {
      newRoute.didChangeNext(null);
    }
    if (index > 0)
      _history[index - 1].didChangeNext(newRoute);
    for (NavigatorObserver observer in widget.observers)
      observer.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    oldRoute.dispose();
    // xxxx
    assert(() { _debugLocked = false; return true; }());
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
    assert(anchorRoute != null);
    assert(anchorRoute._navigator == this);
    assert(_history.indexOf(anchorRoute) > 0);
    replace<T>(oldRoute: _history[_history.indexOf(anchorRoute) - 1], newRoute: newRoute);
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
    assert(_history.isNotEmpty);
    return _history.length > 1 || _history[0].willHandlePopInternally;
  }

  /// Returns the value of the current route's [Route.willPop] method for the
  /// navigator.
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
    final Route<T> route = _history.last;
    assert(route._navigator == this);
    final RoutePopDisposition disposition = await route.willPop();
    if (disposition != RoutePopDisposition.bubble && mounted) {
      if (disposition == RoutePopDisposition.pop)
        pop(result);
      return true;
    }
    return false;
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
  bool pop<T extends Object>([ T result ]) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    // xxx also handle page routes by calling willpop, setting the current
    //     return value, and then call our onPopPage handler
    final Route<dynamic> route = _history.last;
    assert(route._navigator == this);
    bool debugPredictedWouldPop;
    assert(() { debugPredictedWouldPop = !route.willHandlePopInternally; return true; }());
    if (route.didPop(result ?? route.currentResult)) {
      assert(debugPredictedWouldPop);
      if (_history.length > 1) {
        _history.removeLast();
        // If route._navigator is null, the route called finalizeRoute from
        // didPop, which means the route has already been disposed and doesn't
        // need to be added to _poppedRoutes for later disposal.
        if (route._navigator != null)
          _poppedRoutes.add(route);
        _history.last.didPopNext(route);
        for (NavigatorObserver observer in widget.observers)
          observer.didPop(route, _history.last);
      } else {
        assert(() { _debugLocked = false; return true; }());
        return false;
      }
    } else {
      assert(!debugPredictedWouldPop);
    }
    // xxxx
    assert(() { _debugLocked = false; return true; }());
    _cancelActivePointers();
    return true;
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
    while (!predicate(_history.last))
      pop();
  }

  /// Immediately remove `route` from the navigator, and [Route.dispose] it.
  ///
  /// {@macro flutter.widgets.navigator.removeRoute}
  void removeRoute(Route<dynamic> route) {
    assert(route != null);
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    assert(route._navigator == this);
    final int index = _history.indexOf(route);
    assert(index != -1);
    final Route<dynamic> previousRoute = index > 0 ? _history[index - 1] : null;
    final Route<dynamic> nextRoute = (index + 1 < _history.length) ? _history[index + 1] : null;
    _history.removeAt(index);
    previousRoute?.didChangeNext(nextRoute);
    nextRoute?.didChangePrevious(previousRoute);
    for (NavigatorObserver observer in widget.observers)
      observer.didRemove(route, previousRoute);
    route.dispose();
    // xxxx
    assert(() { _debugLocked = false; return true; }());
    _cancelActivePointers();
  }

  /// Immediately remove a route from the navigator, and [Route.dispose] it. The
  /// route to be replaced is the one below the given `anchorRoute`.
  ///
  /// {@macro flutter.widgets.navigator.removeRouteBelow}
  void removeRouteBelow(Route<dynamic> anchorRoute) {
    assert(!_debugLocked);
    assert(() { _debugLocked = true; return true; }());
    // xxxx this should be replaced with code that reuses the logic above
    // xxx just add the route entry with the appropriate life cycle, then
    //     run the logic to send notifications
    assert(anchorRoute._navigator == this);
    final int index = _history.indexOf(anchorRoute) - 1;
    assert(index >= 0);
    final Route<dynamic> targetRoute = _history[index];
    assert(targetRoute._navigator == this);
    assert(targetRoute.overlayEntries.isEmpty || !overlay.debugIsVisible(targetRoute.overlayEntries.last));
    _history.removeAt(index);
    final Route<dynamic> nextRoute = index < _history.length ? _history[index] : null;
    final Route<dynamic> previousRoute = index > 0 ? _history[index - 1] : null;
    if (previousRoute != null)
      previousRoute.didChangeNext(nextRoute);
    if (nextRoute != null)
      nextRoute.didChangePrevious(previousRoute);
    targetRoute.dispose();
    // xxxx
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
    _poppedRoutes.remove(route);
    route.dispose();
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
            initialEntries: _initialOverlayEntries,
          ),
        ),
      ),
    );
  }
}
