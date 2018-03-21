// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'basic.dart';
import 'binding.dart';
import 'framework.dart';
import 'navigator.dart';
import 'placeholder.dart';

/// The dispatcher for opening and closing pages of an application.
///
/// This widget listens for routing information from the operating system (e.g.
/// an initial route provided on app startup, a new route obtained when an
/// intent is received, or a notification that the user hit the system back
/// button), parses route information into data of type `T`, and then converts
/// that data into [Page] objects that it passes to a [Navigator].
///
/// Additionally, every single part of that previous sentence can be overridden
/// and configured as desired.
///
/// The [routeNameProvider] can be overridden to change how the name of the
/// route is obtained. Any implementation of [ValueListenable<String>]
/// will suffice; the [ValueListenable.value] when the [Router] is first created
/// is used as the initial route, and subsequent notifications are treated as
/// notifications that the operating system pushed a new route.
///
/// The [backButtonDispatcher] can be overridden to change how back button
/// notifications are received. This must be a [BackButtonDispatcher], which is
/// an object which which callbacks can be registered, and which can be chained
/// so that back button presses are delegated to subsidiary routers. The
/// callbacks are invoked to indicate that the user is trying to close the
/// current route (by pressing the system back button); the [Router] ensures
/// that when this callback is invoked, the message is passed to the
/// [parsedRouteHandler] and its result is provided back to the
/// [backButtonDispatcher]. Some platforms don't have back buttons and on those
/// platforms it is completely normal that this notification is never sent.
///
/// The [routeNameParser] can be overridden to change how names obtained from
/// the [routeNameProvider] are interpreted. It must implement the
/// [RouteNameParser] interface, specialized with the same type as the [Router]
/// itself. This type, `T`, represents the data type that the [routeNameParser]
/// will generate.
///
/// The [parsedRouteHandler] can be overridden to change how the output of the
/// [routeNameProvider] is interpreted. It must implement the
/// [ParsedRouteHandler] interface, also specialized with `T`; it takes as input
/// the data (of type `T`) from the [routeNameParser], and is responsible for
/// providing a widget to insert into the widget tree. The [ParsedRouteHandler]
/// interface is also [Listenable]; notifications are taken to mean that the
/// [routeNameParser] needs to rebuild.
///
/// ## Defaults and common alternatives
///
/// {@template flutter.widgets.router.defaults}
/// The [Router.defaults] static method creates a [Router] which assumes that
/// `T`, the currency for parsed route information, is a [List] of
/// [RouteSettings] (`List<RouteSettings>`), and configures it with some default
/// handlers.
///
/// The default [routeNameProvider] is an instance of
/// [DefaultRouteNameProvider], which uses [ui.Window.defaultRouteName] to
/// obtain the initial route, and uses a [WidgetsBindingObserver] to listen to
/// the [SystemChannels.navigation] `pushRoute` notifications.
///
/// The default [backButtonDispatcher] is an instance of
/// [DefaultBackButtonDispatcher], which uses a [WidgetsBindingObserver] to
/// listen to the `popRoute` notifications from [SystemChannels.navigation]. A
/// common alternative is [ChildBackButtonDispatcher], which must be provided
/// the [BackButtonDispatcher] of its ancestor [Router] (available via
/// [Router.of]).
///
/// The default [routeNameParser] is an instance of [DefaultRouteNameParser], which
/// parses the incoming routes as if they were a URL path and query, with each
/// resulting [RouteSettings] being for subsequent segments of the path, and all
/// of the [RouteSettings] sharing a single `Map<String, List<String>>` entry in
/// the [RouteSettings.arguments] [TypedDictionary] representing the query
/// component. See also [Uri.queryParametersAll].
///
/// The default [parsedRouteHandler] is an instance of
/// [DefaultParsedRouteHandler], which converts the list of [RouteSettings] into
/// [Page] objects that it passes to a [Navigator] that it builds in its
/// [ParsedRouteHandler.build] method.
/// {@endtemplate}
///
/// ## Concerns regardyng asynchrony
///
/// Some of the APIs (notably those involving [RouteNameParser] and
/// [ParsedRouteHandler]) are asynchronous.
///
/// When developing objects implementing these APIs, if the work can be done
/// entirely synchronously, then consider using [SynchronousFuture] for the
/// future returned from the relevant methods. This will allow the [Router] to
/// proceed in a completely synchronous way, which removes a number of
/// complications.
///
/// Using asynchronous computation is entirely reasonable, however and the API
/// is designed to support it. For example, maybe a set of images need to be
/// loaded before a route can be shown; waiting for those images to be loaded
/// before [ParsedRouteHandler.pushRoute] returns is a reasonable approach to
/// handle this case.
///
/// If an asynchronous operation is ongoing when a new one is to be started, the
/// precise behavior will depend on the exact circumstances, as follows:
///
/// If the active operation is a [routeNameParser] parsing a new route name:
/// that operation's result, if it ever completes, will be discarded.
///
/// If the active operation is a [parsedRouteHandler] handling a pop request:
/// the previous pop is immediately completed with "false", claiming that the
/// previous pop was not handled (this may cause the application to close).
///
/// If the active operation is a [parsedRouteHandler] handling an initial route
/// or a pushed route, the result depends on the new operation. If the new
/// operation is a pop request, then the original operation's result, if it ever
/// completes, will be discarded. If the new operation is a push request,
/// however, the [routeNameParser] will be requested to start the parsing, and
/// only if that finishes before the original [parsedRouteHandler] request
/// completes will that original request's result be discarded.
///
/// If the identity of the [Router] widget's delegates change while an
/// asynchronous operation is in progress, to keep matters simple, all active
/// asynchronous operations will have their results discarded. It is generally
/// considered unusual for these delegates to change during the lifetime of the
/// [Router].
///
/// If the [Router] itself is disposed while an an asynchronous operation is in
/// progress, all active asynchronous operations will have their results
/// discarded also.
///
/// No explicit signals are provided to the [routeNameParser] or
/// [parsedRouteHandler] to indicate when any of the above happens, so it is
/// strongly recommended that [RouteNameParser] and [ParsedRouteHandler]
/// implementations not perform extensive computation. Waiting for an image to
/// download is fine, since it is minimal work; something more expensive, such
/// as evaluating 1000 years of a detailed world simulation, is best done in a
/// way that can be canceled.
///
/// ## Application architectural design
///
/// An application can have zero, one, or many [Router] widgets, depending on
/// its needs.
///
/// An application might have no [Router] widgets if it has only one "screen",
/// or if the facilities provided by [Navigator] are sufficient.
///
/// A particularly elaborate application might have multiple [Router] widgets,
/// in a tree configuration, with the first handling part of the routing, and
/// then passing the remainder to its descendant [Router]s. In this case, one
/// might expect to see each aspect of the [Router] to be overridden with custom
/// behavior.
///
/// Most applications only need a single [Router].
class Router<T> extends StatefulWidget {
  const Router({
    Key key,
    @required this.routeNameProvider,
    @required this.backButtonDispatcher,
    @required this.routeNameParser,
    @required this.parsedRouteHandler,
  }) : assert(routeNameProvider != null),
       assert(backButtonDispatcher != null),
       assert(routeNameParser != null),
       assert(parsedRouteHandler != null),
       super(key: key);

  /// {@macro flutter.widgets.router.defaults}
  static Router<List<RouteSettings>> defaults(
    ValueListenable<String> routeNameProvider,
    BackButtonDispatcher backButtonDispatcher,
    RouteNameParser<List<RouteSettings>> routeNameParser,
    ParsedRouteHandler<List<RouteSettings>> parsedRouteHandler,
  ) {
    return new Router<List<RouteSettings>>(
      routeNameProvider: routeNameProvider ?? new DefaultRouteNameProvider(),
      backButtonDispatcher: backButtonDispatcher ?? new DefaultBackButtonDispatcher(),
      routeNameParser: routeNameParser ?? new DefaultRouteNameParser(),
      parsedRouteHandler: parsedRouteHandler ?? new DefaultParsedRouteHandler(),
    );
  }

  final ValueListenable<String> routeNameProvider;
  final BackButtonDispatcher backButtonDispatcher;
  final RouteNameParser<T> routeNameParser;
  final ParsedRouteHandler<T> parsedRouteHandler;

  static Router<R> of<R>(BuildContext context) {
    final _RouterScope scope = context.inheritFromWidgetOfExactType(_RouterScope);
    assert(scope != null);
    return scope.routerState.widget;
  }

  @override
  State<Router<T>> createState() => new _RouterState<T>();
}

typedef Future<Q> _AsyncPassthrough<Q>(Q data);

class _RouterState<T> extends State<Router<T>> {
  Object _currentRouteNameParserTransaction;
  Object _currentParsedRouteHandlerTransaction;

  @override
  void initState() {
    super.initState();
    widget.routeNameProvider.addListener(_handleRouteNameProviderNotification);
    widget.backButtonDispatcher.addCallback(_handleBackButtonDispatcherNotification);
    widget.parsedRouteHandler.addListener(_handleParsedRouteHandlerNotification);
    _processInitialRoute();
  }

  @override
  void didUpdateWidget(Router<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routeNameProvider != oldWidget.routeNameProvider ||
        widget.backButtonDispatcher != oldWidget.backButtonDispatcher ||
        widget.routeNameParser != oldWidget.routeNameParser ||
        widget.parsedRouteHandler != oldWidget.parsedRouteHandler) {
      _currentRouteNameParserTransaction = new Object();
      _currentParsedRouteHandlerTransaction = new Object();
    }
    if (widget.routeNameProvider != oldWidget.routeNameProvider) {
      widget.routeNameProvider.removeListener(_handleRouteNameProviderNotification);
      widget.routeNameProvider.addListener(_handleRouteNameProviderNotification);
    }
    if (widget.backButtonDispatcher != oldWidget.backButtonDispatcher) {
      widget.backButtonDispatcher.removeCallback(_handleBackButtonDispatcherNotification);
      widget.backButtonDispatcher.addCallback(_handleBackButtonDispatcherNotification);
    }
    if (widget.parsedRouteHandler != oldWidget.parsedRouteHandler) {
      widget.parsedRouteHandler.removeListener(_handleParsedRouteHandlerNotification);
      widget.parsedRouteHandler.addListener(_handleParsedRouteHandlerNotification);
    }
  }

  @override
  void dispose() {
    widget.routeNameProvider.removeListener(_handleRouteNameProviderNotification);
    widget.backButtonDispatcher.removeCallback(_handleBackButtonDispatcherNotification);
    widget.parsedRouteHandler.removeListener(_handleParsedRouteHandlerNotification);
    _currentRouteNameParserTransaction = null;
    _currentParsedRouteHandlerTransaction = null;
    super.dispose();
  }

  void _processInitialRoute() {
    widget.routeNameParser.parse(widget.routeNameProvider.value)
      .then<T>(_verifyRouteNameParserStillCurrent(_currentRouteNameParserTransaction, widget))
      .then<void>(widget.parsedRouteHandler.init)
      .then<void>(_verifyParsedRouteHandlerPushStillCurrent(_currentParsedRouteHandlerTransaction, widget))
      .then<void>(_rebuild);
  }

  void _handleRouteNameProviderNotification() {
    _currentRouteNameParserTransaction = new Object();
    widget.routeNameParser.parse(widget.routeNameProvider.value)
      .then<T>(_verifyRouteNameParserStillCurrent(_currentRouteNameParserTransaction, widget))
      .then<void>(widget.parsedRouteHandler.pushRoute)
      .then<void>(_verifyParsedRouteHandlerPushStillCurrent(_currentParsedRouteHandlerTransaction, widget))
      .then<void>(_rebuild);
  }

  Future<bool> _handleBackButtonDispatcherNotification() {
    _currentRouteNameParserTransaction = new Object();
    _currentParsedRouteHandlerTransaction = new Object();
    return widget.parsedRouteHandler.popRoute()
      .then<RoutePopDisposition>(_verifyParsedRouteHandlerPopStillCurrent(_currentParsedRouteHandlerTransaction, widget))
      .then<bool>((RoutePopDisposition value) async {
        switch (value) {
          case RoutePopDisposition.pop:
            setState(() { /* parsedRouteHandler is ready to rebuild */ });
            return true;
          case RoutePopDisposition.doNotPop:
            // parsedRouteHandler does not require a rebuild
            return true;
          case RoutePopDisposition.bubble:
            return false;
        }
        return false;
      });
  }

  _AsyncPassthrough<T> _verifyRouteNameParserStillCurrent(Object transaction, Router<T> originalWidget) {
    return (T data) {
      if (transaction == _currentRouteNameParserTransaction &&
          widget.routeNameProvider == originalWidget.routeNameProvider &&
          widget.backButtonDispatcher == originalWidget.backButtonDispatcher &&
          widget.routeNameParser == originalWidget.routeNameParser &&
          widget.parsedRouteHandler == originalWidget.parsedRouteHandler) {
        _currentParsedRouteHandlerTransaction = new Object();
        return new SynchronousFuture<T>(data);
      }
      return new Completer<T>().future; // won't ever complete
    };
  }

  _AsyncPassthrough<void> _verifyParsedRouteHandlerPushStillCurrent(Object transaction, Router<T> originalWidget) {
    return (void data) {
      if (transaction == _currentParsedRouteHandlerTransaction &&
          widget.routeNameProvider == originalWidget.routeNameProvider &&
          widget.backButtonDispatcher == originalWidget.backButtonDispatcher &&
          widget.routeNameParser == originalWidget.routeNameParser &&
          widget.parsedRouteHandler == originalWidget.parsedRouteHandler)
        return new SynchronousFuture<void>(null);
      return new Completer<void>().future; // won't ever complete
    };
  }

  _AsyncPassthrough<RoutePopDisposition> _verifyParsedRouteHandlerPopStillCurrent(Object transaction, Router<T> originalWidget) {
    return (RoutePopDisposition data) {
      if (transaction == _currentParsedRouteHandlerTransaction &&
          widget.routeNameProvider == originalWidget.routeNameProvider &&
          widget.backButtonDispatcher == originalWidget.backButtonDispatcher &&
          widget.routeNameParser == originalWidget.routeNameParser &&
          widget.parsedRouteHandler == originalWidget.parsedRouteHandler)
        return new SynchronousFuture<RoutePopDisposition>(data);
      return new SynchronousFuture<RoutePopDisposition>(RoutePopDisposition.bubble);
    };
  }

  Future<void> _rebuild(void value) {
    setState(() { /* parsedRouteHandler is ready to rebuild */ });
    return new SynchronousFuture<void>(null);
  }

  void _handleParsedRouteHandlerNotification() {
    setState(() { /* parsedRouteHandler wants to rebuild */ });
  }

  @override
  Widget build(BuildContext context) {
    return new _RouterScope(
      routeNameProvider: widget.routeNameProvider,
      backButtonDispatcher: widget.backButtonDispatcher,
      routeNameParser: widget.routeNameParser,
      parsedRouteHandler: widget.parsedRouteHandler,
      routerState: this,
      child: new Builder(
        builder: widget.parsedRouteHandler.build,
      ),
    );
  }
}

class _RouterScope extends InheritedWidget {
  const _RouterScope({
    Key key,
    @required this.routeNameProvider,
    @required this.backButtonDispatcher,
    @required this.routeNameParser,
    @required this.parsedRouteHandler,
    @required this.routerState,
    @required Widget child,
  }) : assert(routeNameProvider != null),
       assert(backButtonDispatcher != null),
       assert(routeNameParser != null),
       assert(parsedRouteHandler != null),
       assert(routerState != null),
       super(key: key, child: child);

  final ValueListenable<String> routeNameProvider;
  final BackButtonDispatcher backButtonDispatcher;
  final RouteNameParser<dynamic> routeNameParser;
  final ParsedRouteHandler<dynamic> parsedRouteHandler;
  final _RouterState<dynamic> routerState;

  @override
  bool updateShouldNotify(_RouterScope oldWidget) {
    return routeNameProvider != oldWidget.routeNameProvider
        || backButtonDispatcher != oldWidget.backButtonDispatcher
        || routeNameParser != oldWidget.routeNameParser
        || parsedRouteHandler != oldWidget.parsedRouteHandler
        || routerState != oldWidget.routerState;
  }
}

/// A class that can be extended or mixed in that invokes a single callback,
/// which then returns a value.
///
/// While multiple callbacks can be registered, when a notification is
/// dispatched there must be only a single callback. The return values of
/// multiple callbacks are not aggregated.
///
/// `T` is the return value expected from the callback.
///
/// See also:
///
///  * [Listenable] and its subclasses, which provide a similar mechanism for
///    one-way signalling.
class _CallbackHookProvider<T> {
  ObserverList<ValueGetter<T>> _callbacks = new ObserverList<ValueGetter<T>>();

  /// Asserts that the object has not been disposed.
  ///
  /// Always returns true (or throws). This is intended to be used from asserts
  /// of methods of this class:
  ///
  /// ```dart
  /// assert(debugAssertNotDisposed());
  /// ```
  @protected
  bool debugAssertNotDisposed() {
    assert(() {
      if (_callbacks == null) {
        throw new FlutterError(
          'A $runtimeType was used after being disposed.\n'
          'Once you have called dispose() on a $runtimeType, it can no longer be used.'
        );
      }
      return true;
    }());
    return true;
  }

  /// Whether a callback is currently registered.
  @protected
  bool get hasCallbacks {
    assert(debugAssertNotDisposed());
    return _callbacks.isNotEmpty;
  }

  /// Register the callback to be called when the object changes.
  ///
  /// This method must not be called after [dispose] has been called.
  ///
  /// If other callbacks have already been registered, they must be removed
  /// (with [removeCallback]) before the callback is next called.
  void addCallback(ValueGetter<T> callback) {
    assert(debugAssertNotDisposed());
    _callbacks.add(callback);
  }

  /// Remove a previously registered callback.
  ///
  /// If the given callback is not registered, the call is ignored.
  ///
  /// This method must not be called after [dispose] has been called.
  void removeCallback(ValueGetter<T> callback) {
    assert(debugAssertNotDisposed());
    _callbacks.remove(callback);
  }

  /// Discards any resources used by the object. After this is called, the
  /// object is not in a usable state and should be discarded (calls to
  /// [addCallback] and [removeCallback] will throw after the object is
  /// disposed).
  ///
  /// This method should only be called by the object's owner.
  @mustCallSuper
  void dispose() {
    assert(debugAssertNotDisposed());
    _callbacks = null;
  }

  /// Calls the (single) registered callback and returns its result.
  ///
  /// If no callback is registered, or if the callback throws, returns
  /// `defaultValue`.
  ///
  /// Call this method whenever the callback is to be invoked. If there is more
  /// than one callback registered, this method will throw a [StateError].
  ///
  /// Exceptions thrown by callbacks will be caught and reported using
  /// [FlutterError.reportError].
  ///
  /// This method must not be called after [dispose] has been called.
  @protected
  T invokeCallback(T defaultValue) {
    assert(debugAssertNotDisposed());
    if (_callbacks.isEmpty)
      return defaultValue;
    try {
      return _callbacks.single();
    } catch (exception, stack) {
      FlutterError.reportError(new FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'foundation library',
        context: 'while invoking the callback for $runtimeType',
        informationCollector: (StringBuffer information) {
          information.writeln('The $runtimeType that invoked the callback was:');
          information.write('  $this');
        }
      ));
      return defaultValue;
    }
  }
}

/// Report to a [Router] when the user taps the back button on platforms that
/// support back buttons (such as Android).
///
/// When [Router] widgets are nested, consider using a
/// [NestedBackButtonDispatcher], passing it the parent [BackButtonDispatcher],
/// so that the back button requests get dispatched to the appropriate [Router].
/// To make this work properly, it's important that whenever a [Router] thinks
/// it should get the back button messages (e.g. after the user taps inside it),
/// it calls [takePriority] on its [BackButtonDispatcher] (or
/// [ChildBackButtonDispatcher]) instance.
///
/// The class takes a single callback, which must return a [Future<bool>]. The
/// callback's semantics match [WidgetsFlutterBinding.didPopRoute]'s, namely,
/// the callback should return a future that completes to true if it can handle
/// the pop request, and a future that completes to false otherwise.
abstract class BackButtonDispatcher extends _CallbackHookProvider<Future<bool>> {
  LinkedHashSet<ChildBackButtonDispatcher> _children;

  @override
  bool get hasCallbacks => super.hasCallbacks || _children.isNotEmpty;

  @override
  Future<bool> invokeCallback(Future<bool> defaultValue) {
    assert(debugAssertNotDisposed());
    if (_children != null && _children.isNotEmpty)
      return _children.last.notifiedByParent(defaultValue);
    return super.invokeCallback(defaultValue);
  }

  /// Make this [BackButtonDispatcher] take priority among its peers.
  ///
  /// This has no effect when a [BackButtonDispatcher] has no parents and no
  /// children. If a [BackButtonDispatcher] does have parents or children,
  /// however, it causes this object to be the one to dispatch the notification
  /// when the parent would normally notify its callback.
  void takePriority() {
    assert(debugAssertNotDisposed());
    if (_children != null)
      _children.clear();
  }

  /// Mark the given child as taking priority over this object and the other
  /// children.
  ///
  /// This causes [invokeCallback] to defer to the given child instead of
  /// calling this object's callback.
  ///
  /// Children are stored in a list, so that if the current child is removed
  /// using [forget], a previous child will return to take its place. When
  /// [takePriority] is called, the list is cleared.
  ///
  /// Calling this again without first calling [forget] moves the child back to
  /// the head of the list.
  //
  // (Actually it moves it to the end of the list and we treat the end of the
  // list to be the priority end, but that's an implementation detail.)
  void deferTo(ChildBackButtonDispatcher child) {
    assert(debugAssertNotDisposed());
    _children ??= new LinkedHashSet<ChildBackButtonDispatcher>();
    if (_children.contains(child))
      _children.remove(child);
    _children.add(child);
  }

  /// Causes the given child to be removed from the list of children to which
  /// this object might defer, as if [deferTo] had never been called for that
  /// child.
  ///
  /// This should only be called once per child, even if [deferTo] was called
  /// multiple times for that child.
  ///
  /// If no children are left in the list, this object will stop defering to its
  /// children. (This is not the same as calling [takePriority], since, if this
  /// object itself is a [ChildBackButtonDispatcher], [takePriority] would
  /// additionally attempt to claim priority from its parent, whereas removing
  /// the last child does not.)
  void forget(ChildBackButtonDispatcher child) {
    assert(debugAssertNotDisposed());
    assert(_children != null);
    assert(_children.contains(child));
    _children.remove(child);
  }
}

/// A variant of [BackButtonDispatcher] which listens to notifications from a
/// parent back button dispatcher, and can take priority from its parent for the
/// handling of such notifications.
///
/// Useful when [Router]s are being nested within each other.
///
/// Use [Router.of] to obtain a reference to the nearest ancestor [Router], from
/// which the [Router.backButtonDispatcher] can be found, and then used as the
/// [parent] of the [ChildBackButtonDispatcher].
class ChildBackButtonDispatcher extends BackButtonDispatcher {
  /// Creates a back button dispatcher that acts as the child of another.
  ///
  /// The [parent] must not be null and must not be disposed before this object.
  ChildBackButtonDispatcher(this.parent) : assert(parent != null);

  /// The back button dispatcher that this object will attempt to take priority
  /// over when [takePriority] is called.
  ///
  /// The parent must not be disposed before this object.
  final BackButtonDispatcher parent;

  @protected
  Future<bool> notifiedByParent(Future<bool> defaultValue) {
    return invokeCallback(defaultValue);
  }

  @override
  void takePriority() {
    parent.deferTo(this);
    super.takePriority();
  }

  @override
  void deferTo(ChildBackButtonDispatcher child) {
    parent.deferTo(this);
    super.deferTo(child);
  }

  @override
  void dispose() {
    parent.forget(this);
    super.dispose();
  }
}

abstract class RouteNameParser<T> {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const RouteNameParser();

  /// Converts the given string into parsed data to pass to a
  /// [ParsedRouteHandler].
  ///
  /// The method should return a future which completes when the parsing is
  /// complete. The parsing may be asynchronous if, e.g., the parser needs to
  /// communicate with the OEM thread to obtain additional data about the route.
  ///
  /// Consider using a [SynchronousFuture] if the result can be computed
  /// synchronously, so that the [Router] does not need to wait for the next
  /// microtask to pass the data to the [ParsedRouteHandler].
  Future<T> parse(String routeName);
}

abstract class ParsedRouteHandler<T> implements Listenable {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const ParsedRouteHandler();

  /// Called by the [Router] at startup with the structure that the
  /// [RouteNameParser] obtained from parsing the initial route.
  ///
  /// This should configure the [ParsedRouteHandler] so that when [build] is
  /// invoked, it will create a widget tree that matches the initial route.
  ///
  /// The method should return a future which completes when the route handler
  /// is ready to build the initial route. The [build] method may be called
  /// before the future completes, in which case it should return a widget tree
  /// that represents a loading state.
  ///
  /// Consider using a [SynchronousFuture] if the result can be computed
  /// synchronously, so that the [Router] does not need to wait until after the
  /// first frame to schedule the initial build.
  Future<void> init(T configuration);

  /// Called by the [Router] when the [Router.routeNameProvider] reports that a
  /// new route has been pushed to the application by the operating system.
  ///
  /// The method should return a future which completes with the value true when
  /// the route handler is ready to build the new route. The [build] method may
  /// be called before the future completes, in which case it should return a
  /// widget tree that represents the previous state.
  ///
  /// The method can return a future which completes with the value false to
  /// indicate that the new route is being ignored and that the [Router] need
  /// not rebuild.
  ///
  /// Consider using a [SynchronousFuture] if the result can be computed
  /// synchronously, so that the [Router] does not need to wait for the next
  /// microtask to schedule a build.
  Future<bool> pushRoute(T configuration);

  /// Called by the [Router] when the [Router.backButtonDispatcher] reports that
  /// the operating system is requesting that the current route be popped.
  ///
  /// The method should return a future which completes to one of these three
  /// values:
  ///
  /// * [RoutePopDisposition.pop]: indicates that the route handler was able to
  ///   do something with the value and is ready to update the widget tree
  ///   returned by [build].
  ///
  /// * [RoutePopDisposition.doNotPop]: indicates that the request is being
  ///   ignored and that the [Router] need not rebuild. This may happen if, for
  ///   instance, the [ParsedRouteHandler] communicated with a [Navigator] and
  ///   the [Navigator] reported that it handled the pop itself.
  ///
  /// * [RoutePopDisposition.bubble]: indicates that the request could not be
  ///   handled (e.g. there's only one route being shown), and the request
  ///   should be sent to some higher authority. Typically, this means allowing
  ///   the [WidgetsFlutterBinding] to handle the request; by default, this
  ///   calls [SystemNavigator.pop] which closes the application.
  ///
  /// Consider using a [SynchronousFuture] if the result can be computed
  /// synchronously, so that the [Router] does not need to wait for the next
  /// microtask to schedule a build.
  Future<RoutePopDisposition> popRoute();

  /// Called by the [Router] to obtain the widget tree that represents the
  /// current state.
  ///
  /// This is called whenever the [init] method's future completes, the
  /// [pushRoute] method's future completes with the value true, the [popRoute]
  /// method's future completes with the value true, or this object notifies its
  /// clients (see the [Listenable] interface, which this interface includes).
  /// In addition, it may be called at other times. It is important, therefore,
  /// that the methods above do not update the state that the [build] method
  /// uses before they complete their respective futures.
  ///
  /// Typically this method returns a suitably-configured [Navigator].
  ///
  /// This method must not return null.
  ///
  /// The `context` is the [Router]'s build context.
  Widget build(BuildContext context);
}


// DEFAULT IMPLEMENTATIONS

class DefaultRouteNameProvider extends ValueNotifier<String> with WidgetsBindingObserver {
  DefaultRouteNameProvider() : super(ui.window.defaultRouteName) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPushRoute(String route) async {
    if (hasListeners) {
      notifyListeners();
      return true;
    }
    return false;
  }
}

class DefaultBackButtonDispatcher extends BackButtonDispatcher with WidgetsBindingObserver {
  DefaultBackButtonDispatcher() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() => invokeCallback(new Future<bool>.value(false));
}

class DefaultRouteNameParser extends RouteNameParser<List<RouteSettings>> {
  @override
  Future<List<RouteSettings>> parse(String routeName) {
    final int startOfQuery = routeName.indexOf('?');
    final String path = routeName.substring(0, startOfQuery >= 0 ? startOfQuery : routeName.length);
    final String query = startOfQuery >= 0 ? routeName.substring(startOfQuery + 1, routeName.length) : '';
    final Uri syntheticUrl = new Uri(path: path, query: query);
    final List<String> paths = <String>['/'];
    if (syntheticUrl.pathSegments.isNotEmpty) {
      final StringBuffer path = new StringBuffer('/');
      for (String segment in syntheticUrl.pathSegments) {
        path.write(segment);
        paths.add(path.toString());
      }
    }
    final TypedDictionary arguments = new TypedDictionary()
      ..set<Map<String, List<String>>>(syntheticUrl.queryParametersAll);
    final List<RouteSettings> result = <RouteSettings>[];
    for (String routePath in paths)
      result.add(new RouteSettings(name: routePath, arguments: arguments));
    return new SynchronousFuture<List<RouteSettings>>(result);
  }
}

class DefaultParsedRouteHandler extends ParsedRouteHandler<List<RouteSettings>> with ChangeNotifier {
  List<RouteSettings> _currentSettings;

  @override
  Future<void> init(List<RouteSettings> configuration) {
    _currentSettings = configuration;
    /*
      String initialRouteName = widget.initialRoute ?? Navigator.defaultRouteName;
      if (initialRouteName.startsWith('/') && initialRouteName.length > 1) {
        initialRouteName = initialRouteName.substring(1); // strip leading '/'
        assert(Navigator.defaultRouteName == '/');
        final List<String> plannedInitialRouteNames = <String>[
          Navigator.defaultRouteName,
        ];
        final List<Route<dynamic>> plannedInitialRoutes = <Route<dynamic>>[
          _routeNamed<dynamic>(Navigator.defaultRouteName, allowNull: true),
        ];
        final List<String> routeParts = initialRouteName.split('/');
        if (initialRouteName.isNotEmpty) {
          String routeName = '';
          for (String part in routeParts) {
            routeName += '/$part';
            plannedInitialRouteNames.add(routeName);
            plannedInitialRoutes.add(_routeNamed<dynamic>(routeName, allowNull: true));
          }
        }
        if (plannedInitialRoutes.contains(null)) {
          assert(() {
            FlutterError.reportError(
              new FlutterErrorDetails( // ignore: prefer_const_constructors, https://github.com/dart-lang/sdk/issues/29952
                exception:
                  'Could not navigate to initial route.\n'
                  'The requested route name was: "/$initialRouteName"\n'
                  'The following routes were therefore attempted:\n'
                  ' * ${plannedInitialRouteNames.join("\n * ")}\n'
                  'This resulted in the following objects:\n'
                  ' * ${plannedInitialRoutes.join("\n * ")}\n'
                  'One or more of those objects was null, and therefore the initial route specified will be '
                  'ignored and "${Navigator.defaultRouteName}" will be used instead.'
              ),
            );
            return true;
          }());
          push(_routeNamed<Object>(Navigator.defaultRouteName));
        } else {
          plannedInitialRoutes.forEach(push);
        }
      } else {
        Route<Object> route;
        if (initialRouteName != Navigator.defaultRouteName)
          route = _routeNamed<Object>(initialRouteName, allowNull: true);
        route ??= _routeNamed<Object>(Navigator.defaultRouteName);
        push(route);
      }
      for (Route<dynamic> route in _history)
        _initialOverlayEntries.addAll(route.overlayEntries);
    */
    return new SynchronousFuture<void>(null);
  }

  /*
    Route<T> _routeNamed<T>(String name, { bool allowNull: false, TypedDictionary arguments: TypedDictionary.empty }) {
      assert(!_debugLocked);
      assert(name != null);
      final RouteSettings settings = new RouteSettings(
        name: name,
        isInitialRoute: _history.isEmpty,
        arguments: arguments,
      );
      Route<T> route = widget.onGenerateRoute(settings);
      if (route == null && !allowNull) {
        assert(() {
          if (widget.onUnknownRoute == null) {
            throw new FlutterError(
              'If a Navigator has no onUnknownRoute, then its onGenerateRoute must never return null.\n'
              'When trying to build the route "$name", onGenerateRoute returned null, but there was no '
              'onUnknownRoute callback specified.\n'
              'The Navigator was:\n'
              '  $this'
            );
          }
          return true;
        }());
        route = widget.onUnknownRoute(settings);
        assert(() {
          if (route == null) {
            throw new FlutterError(
              'A Navigator\'s onUnknownRoute returned null.\n'
              'When trying to build the route "$name", both onGenerateRoute and onUnknownRoute returned '
              'null. The onUnknownRoute callback should never return null.\n'
              'The Navigator was:\n'
              '  $this'
            );
          }
          return true;
        }());
      }
      return route;
    }
  */

/*
    this.initialRoute,
    @required this.onGenerateRoute,
    this.onUnknownRoute,

  /// The name of the first route to show.
  ///
  /// By default, this defers to [dart:ui.Window.defaultRouteName].
  ///
  /// If this string contains any `/` characters, then the string is split on
  /// those characters and substrings from the start of the string up to each
  /// such character are, in turn, used as routes to push.
  ///
  /// For example, if the route `/stocks/HOOLI` was used as the [initialRoute],
  /// then the [Navigator] would push the following routes on startup: `/`,
  /// `/stocks`, `/stocks/HOOLI`. This enables deep linking while allowing the
  /// application to maintain a predictable route history.
  final String initialRoute;

  /// Called when [onGenerateRoute] fails to generate a route.
  ///
  /// This callback is typically used for error handling. For example, this
  /// callback might always generate a "not found" page that describes the route
  /// that wasn't found.
  ///
  /// Unknown routes can arise either from errors in the app or from external
  /// requests to push routes, such as from Android intents.
  final RouteFactory onUnknownRoute;

  /// The default name for the [initialRoute].
  ///
  /// See also:
  ///
  ///  * [dart:ui.Window.defaultRouteName], which reflects the route that the
  ///    application was started with.
  static const String defaultRouteName = '/';
*/

  @override
  Future<bool> pushRoute(List<RouteSettings> configuration) {
    _currentSettings = configuration;
    return new SynchronousFuture<bool>(true);
  }

  @override
  Future<RoutePopDisposition> popRoute() {
    if (_currentSettings.length > 1) {
      _currentSettings.removeLast();
      return new SynchronousFuture<RoutePopDisposition>(RoutePopDisposition.pop);
    }
    return new SynchronousFuture<RoutePopDisposition>(RoutePopDisposition.bubble);
  }

  @override
  Widget build(BuildContext context) {
    // TODO(ianh): Return a suitably-configured [Navigator] once Navigator
    // supports having its history route rewritten in a reactive style.
    return const Placeholder();
  }
}
