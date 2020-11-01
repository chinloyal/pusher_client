import 'dart:developer';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pusher_client/pusher_client.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  PusherClient pusher;
  Channel channel;

  @override
  void initState() {
    super.initState();
    pusherTest();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> pusherTest() async {
    print('start');
    pusher = new PusherClient(
      "dev-key",
      PusherOptions(
        host: 'localhost',
        wsPort: 6001,
        wssPort: 6001,
        encrypted: false,
        auth: PusherAuth(
          'http://localhost:8000/api/broadcasting/auth',
          headers: {
            'Authorization':
                'Bearer Esyz231fh2RPx8CbOyY5kZ9JHlL3m9ufSJd7Vmw7RtYT1JSRqUalQuVVVWEkYemVwRoO1gP3A4gALyQ4',
          },
        ),
      ),
      enableLogging: true,
    );

    pusher.onConnectionStateChange((state) {
      log("previousState: ${state.previousState}, currentState: ${state.currentState}");
    });

    pusher.onConnectionError((error) {
      log("error: ${error.message}");
    });
    channel = pusher.subscribe("private-qpin.1");

    channel.bind('stranger.sent.message.event', (event) {
      log(event.data);
    });

    channel.bind('demo.event', (event) {
      log("DEMO EVENT" + event.toString());
    });
    print("done");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Example Pusher App'),
        ),
        body: Center(
            child: Column(
          children: [
            RaisedButton(
              child: Text('Unsubscribe'),
              onPressed: () {
                pusher.unsubscribe('private-qpin.1');
              },
            ),
            RaisedButton(
              child: Text('Unbind 1'),
              onPressed: () {
                channel.unbind('stranger.sent.message.event');
              },
            ),
            RaisedButton(
              child: Text('Unbind 2'),
              onPressed: () {
                channel.unbind('demo.event');
              },
            ),
            RaisedButton(
              child: Text('Bind 1'),
              onPressed: () {
                channel.bind('demo.event', (event) {
                  log("DEMO EVENT" + event.toString());
                });
              },
            ),
            RaisedButton(
              child: Text('Trigger 1'),
              onPressed: () {
                channel.trigger('demo.event', {'message': 'I am kl :)'});
              },
            ),
          ],
        )),
      ),
    );
  }
}
