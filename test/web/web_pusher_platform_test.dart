@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_client/src/platform/pusher_platform.dart';
import 'package:pusher_client/src/web/web_pusher_platform.dart';
import 'package:web/web.dart' as web;

/// A tiny stand-in for pusher-js with the API surface the plugin uses.
const _fakePusherJs = r'''
(function () {
  function Dispatcher() { this.cbs = {}; this.global = []; }
  Dispatcher.prototype.bind = function (n, f) { (this.cbs[n] = this.cbs[n] || []).push(f); };
  Dispatcher.prototype.unbind = function (n, f) {
    if (!n) { this.cbs = {}; return; }
    this.cbs[n] = (this.cbs[n] || []).filter(function (x) { return x !== f; });
  };
  Dispatcher.prototype.bind_global = function (f) { this.global.push(f); };
  Dispatcher.prototype.unbind_global = function (f) {
    this.global = f ? this.global.filter(function (x) { return x !== f; }) : [];
  };
  Dispatcher.prototype.emit = function (n, d, m) {
    this.global.slice().forEach(function (g) { g(n, d); });
    (this.cbs[n] || []).slice().forEach(function (f) { f(d, m); });
  };
  function Channel(name) {
    Dispatcher.call(this); this.name = name; this.triggered = [];
    if (name.indexOf('presence-') === 0) this.members = { count: 0, each: function () {} };
  }
  Channel.prototype = Object.create(Dispatcher.prototype);
  Channel.prototype.trigger = function (e, d) { this.triggered.push([e, d]); return true; };
  function Pusher(key, options) {
    this.key = key; this.options = options; this.channels = {};
    this.connection = new Dispatcher();
    this.connection.state = 'initialized'; this.connection.socket_id = null;
    this.calls = [];
    Pusher.instances.push(this);
  }
  Pusher.instances = [];
  Pusher.prototype.connect = function () { this.calls.push('connect'); };
  Pusher.prototype.disconnect = function () { this.calls.push('disconnect'); };
  Pusher.prototype.subscribe = function (n) {
    this.calls.push('subscribe:' + n);
    return this.channels[n] || (this.channels[n] = new Channel(n));
  };
  Pusher.prototype.unsubscribe = function (n) { this.calls.push('unsubscribe:' + n); delete this.channels[n]; };
  Pusher.prototype.channel = function (n) { return this.channels[n]; };
  Pusher.prototype.setState = function (s, id) {
    var prev = this.connection.state; this.connection.state = s;
    this.connection.socket_id = id || null;
    this.connection.emit('state_change', { previous: prev, current: s });
  };
  window.Pusher = Pusher;
})();
''';

@JS('Pusher')
extension type _FakePusher._(JSObject _) implements JSObject {
  external static JSArray<_FakePusherInstance> get instances;
}

extension type _FakePusherInstance._(JSObject _) implements JSObject {
  external JSObject get options;
  external JSObject get connection;
  external JSArray<JSString> get calls;
  external void setState(String state, [String? socketId]);
  external JSObject channel(String name);
}

@JS('eval')
external JSAny? _eval(String code);

void main() {
  setUpAll(() {
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..text = _fakePusherJs;
    web.document.head!.append(script);
  });

  late WebPusherPlatform platform;
  late List<Map<String, Object?>> events;
  late StreamSubscription<Map<String, Object?>> sub;
  Future<Map<String, Object?>> Function(String, String, String)? authImpl;

  _FakePusherInstance fake(int i) => _FakePusher.instances.toDart[i];
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() async {
    _FakePusher.instances.length = 0;
    platform = WebPusherPlatform();
    authImpl = null;
    platform.authorizeHandler = (id, ch, sock) => authImpl!(id, ch, sock);
    events = [];
    sub = platform.events.listen(events.add);
    await platform.init(
        'a',
        'key',
        {
          'cluster': 'eu',
          'host': null,
          'wsPort': 80,
          'wssPort': 443,
          'useTLS': true,
          'activityTimeout': 1000,
          'pongTimeout': 500,
          'maxReconnectionAttempts': 6,
          'maxReconnectGapInSeconds': 30,
          'hasAuthorizer': true,
        },
        false);
  });

  tearDown(() async {
    await sub.cancel();
    await platform.disposeAll();
  });

  test('registerWith-style assignment works', () {
    PusherPlatform.instance = platform;
    expect(PusherPlatform.instance, same(platform));
  });

  test('passes mapped options to pusher-js', () {
    final opts = fake(0).options.dartify()! as Map;
    expect(opts['cluster'], 'eu');
    expect(opts['forceTLS'], true);
    expect(opts['activityTimeout'], 1000);
    expect(opts['pongTimeout'], 500);
    expect(opts['enabledTransports'], ['ws', 'wss']);
  });

  test('state changes and socket id', () async {
    await platform.connect('a');
    expect(fake(0).calls.toDart.map((e) => e.toDart), contains('connect'));
    fake(0).setState('connecting');
    fake(0).setState('connected', '12.34');
    fake(0).setState('unavailable');
    await pump();
    expect(events.map((e) => e['currentState']),
        ['CONNECTING', 'CONNECTED', 'RECONNECTING']);
    await pump();
    expect(events[1]['socketId'], '12.34');
    await pump();
    expect(events[1]['previousState'], 'CONNECTING');
    await pump();
    expect(events[2]['socketId'], isNull);
  });

  test('connection errors', () async {
    fake(0).connection.callMethod<JSAny?>(
          'emit'.toJS,
          'error'.toJS,
          {
            'type': 'WebSocketError',
            'error': {
              'data': {'code': 4001, 'message': 'App key not found'},
            },
          }.jsify(),
        );
    await pump();
    expect(events.single, {
      'instanceId': 'a',
      'type': 'connectionError',
      'message': 'App key not found',
      'code': '4001',
      'exception': 'WebSocketError',
    });
  });

  test('forwards events once, JSON-encoding objects', () async {
    await platform.subscribe('a', 'chan');
    await platform.subscribe('a', 'chan'); // idempotent
    final ch = fake(0).channel('chan');
    ch.callMethod<JSAny?>('emit'.toJS, 'evt'.toJS, {'x': 1}.jsify());
    ch.callMethod<JSAny?>('emit'.toJS, 'str'.toJS, 'hello'.toJS);
    ch.callMethod<JSAny?>(
        'emit'.toJS, 'pusher:subscription_succeeded'.toJS, {}.jsify());
    ch.callMethod<JSAny?>('emit'.toJS, 'pusher_internal:x'.toJS, 'n'.toJS);
    await pump();
    expect(events.map((e) => [e['eventName'], e['data']]), [
      ['evt', '{"x":1}'],
      ['str', 'hello'],
      ['pusher:subscription_succeeded', '{}'],
    ]);
    await pump();
    expect(events.first['channelName'], 'chan');
    await pump();
    expect(events.first['type'], 'event');
  });

  test('client event user_id metadata', () async {
    await platform.subscribe('a', 'presence-room');
    fake(0).channel('presence-room').callMethod<JSAny?>(
          'emit'.toJS,
          'client-x'.toJS,
          '{"a":1}'.toJS,
          {'user_id': 'u9'}.jsify(),
        );
    await pump();
    expect(events.single['userId'], 'u9');
    await pump();
    expect(events.single['data'], '{"a":1}');
  });

  test('presence members conversion', () async {
    await platform.subscribe('a', 'presence-room');
    final ch = fake(0).channel('presence-room');
    final members = _eval('''({
      count: 2,
      each: function (cb) {
        cb({id: '1', info: {name: 'A'}});
        cb({id: '2', info: null});
      }
    })''');
    ch.callMethod<JSAny?>(
        'emit'.toJS, 'pusher:subscription_succeeded'.toJS, members);
    ch.callMethod<JSAny?>(
        'emit'.toJS,
        'pusher:member_added'.toJS,
        {
          'id': '3',
          'info': {'n': 1}
        }.jsify());
    ch.callMethod<JSAny?>(
        'emit'.toJS, 'pusher:member_removed'.toJS, {'id': '3'}.jsify());
    await pump();
    expect(jsonDecode(events[0]['data']! as String), {
      'presence': {
        'count': 2,
        'ids': ['1', '2'],
        'hash': {
          '1': {'name': 'A'},
          '2': null,
        },
      },
    });
    await pump();
    expect(jsonDecode(events[1]['data']! as String), {
      'user_id': '3',
      'user_info': {'n': 1}
    });
    await pump();
    expect(events[1]['userId'], '3');
    await pump();
    expect(jsonDecode(events[2]['data']! as String), {'user_id': '3'});
    await pump();
    expect(events[2]['userId'], '3');
  });

  test('custom auth handler success omits nulls', () async {
    authImpl = (id, ch, sock) async {
      expect([id, ch, sock], ['a', 'private-x', '1.2']);
      return {'auth': 'k:sig', 'channel_data': null, 'shared_secret': null};
    };
    final handler = ((fake(0).options['channelAuthorization']!
        as JSObject)['customHandler']! as JSFunction);
    final done = Completer<List<Object?>>();
    handler.callAsFunction(
      null,
      {'channelName': 'private-x', 'socketId': '1.2'}.jsify(),
      ((JSAny? err, JSAny? data) =>
          done.complete([err.dartify(), data.dartify()])).toJS,
    );
    final result = await done.future;
    expect(result[0], isNull);
    expect(result[1], {'auth': 'k:sig'});
  });

  test('custom auth failure becomes normalised subscription_error', () async {
    authImpl = (id, ch, sock) => Future.error(PlatformException(
          code: 'AUTH_ERROR',
          message: 'forbidden',
          details: {'status': 403},
        ));
    await platform.subscribe('a', 'private-x');
    final handler = ((fake(0).options['channelAuthorization']!
        as JSObject)['customHandler']! as JSFunction);
    final done = Completer<String?>();
    handler.callAsFunction(
      null,
      {'channelName': 'private-x', 'socketId': '1.2'}.jsify(),
      ((JSAny? err, JSAny? data) =>
              done.complete((err! as JSObject)['message'].dartify() as String?))
          .toJS,
    );
    expect(await done.future, 'forbidden');
    // pusher-js then emits subscription_error without a status.
    fake(0).channel('private-x').callMethod<JSAny?>(
        'emit'.toJS,
        'pusher:subscription_error'.toJS,
        {'type': 'AuthError', 'error': 'forbidden'}.jsify());
    await pump();
    expect(jsonDecode(events.single['data']! as String),
        {'type': 'AuthError', 'error': 'forbidden', 'status': 403});
  });

  test('trigger validates and passes data through', () async {
    await platform.subscribe('a', 'private-x');
    await platform.trigger('a', 'private-x', 'client-e', '{"k":"v"}');
    final triggered =
        fake(0).channel('private-x')['triggered']! as JSArray<JSArray<JSAny?>>;
    expect(triggered.toDart.single.toDart[0].dartify(), 'client-e');
    expect(triggered.toDart.single.toDart[1].dartify(), '{"k":"v"}');
    await expectLater(
      platform.trigger('a', 'public', 'client-e', '{}'),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'TRIGGER_ERROR')),
    );
    await expectLater(
      platform.trigger('a', 'private-encrypted-x', 'client-e', '{}'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('NO_INSTANCE errors and no-op dispose', () async {
    for (final call in <Future<void> Function()>[
      () => platform.connect('zz'),
      () => platform.disconnect('zz'),
      () => platform.subscribe('zz', 'c'),
      () => platform.unsubscribe('zz', 'c'),
      () => platform.trigger('zz', 'private-c', 'e', '{}'),
      () => platform.getSocketId('zz'),
    ]) {
      await expectLater(
        call(),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'NO_INSTANCE')),
      );
    }
    await platform.dispose('zz');
  });

  test('dispose and disposeAll disconnect and stop events', () async {
    await platform.init('b', 'key2', {'cluster': 'mt1'}, false);
    await platform.subscribe('a', 'chan');
    final ch = fake(0).channel('chan');
    await platform.dispose('a');
    expect(fake(0).calls.toDart.map((e) => e.toDart), contains('disconnect'));
    ch.callMethod<JSAny?>('emit'.toJS, 'late'.toJS, 'x'.toJS);
    fake(0).setState('connecting');
    await pump();
    await pump();
    expect(events, isEmpty);
    await expectLater(platform.connect('a'), throwsA(isA<PlatformException>()));
    await platform.disposeAll();
    expect(fake(1).calls.toDart.map((e) => e.toDart), contains('disconnect'));
    await expectLater(platform.connect('b'), throwsA(isA<PlatformException>()));
  });

  test('getSocketId', () async {
    expect(await platform.getSocketId('a'), isNull);
    fake(0).setState('connected', '5.6');
    expect(await platform.getSocketId('a'), '5.6');
  });
}
