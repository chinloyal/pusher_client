import 'package:flutter/material.dart';
import 'package:pusher_client/pusher_client.dart';

import 'config.dart';

/// One line of the event log.
class LogEntry {
  LogEntry(this.channel, this.event, this.data, this.userId)
      : time = DateTime.now();

  final DateTime time;
  final String? channel;
  final String? event;
  final String? data;
  final String? userId;

  String get timeText {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.config});

  final DemoConfig config;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PusherClient _client;
  final _channelController = TextEditingController();
  final _eventController = TextEditingController(text: 'client-hello');
  final _dataController = TextEditingController(text: '{"message":"hi"}');
  final _log = <LogEntry>[];
  String? _triggerChannel;

  @override
  void initState() {
    super.initState();
    _client = PusherClient(
      widget.config.key,
      widget.config.toOptions(),
      enableLogging: true,
      autoConnect: false,
    );
    _client.onConnectionStateChange((_) => _refresh());
    _client.onConnectionError((error) {
      _add(LogEntry(null, 'connection error', error.toString(), null));
    });
  }

  @override
  void dispose() {
    _client.dispose();
    _channelController.dispose();
    _eventController.dispose();
    _dataController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _add(LogEntry entry) {
    if (!mounted) return;
    setState(() => _log.insert(0, entry));
  }

  void _subscribe() {
    final name = _channelController.text.trim();
    if (name.isEmpty) return;
    if (_client.channel(name) != null) {
      _snack('Already subscribed to $name');
      return;
    }
    final channel = _client.subscribe(name);
    channel.bindGlobal((event) {
      _add(LogEntry(
          event.channelName, event.eventName, event.data, event.userId));
    });
    _channelController.clear();
    setState(() {});
  }

  Future<void> _unsubscribe(String name) async {
    await _client.unsubscribe(name);
    if (_triggerChannel == name) _triggerChannel = null;
    _refresh();
  }

  Future<void> _trigger() async {
    final name = _triggerChannel;
    if (name == null) return;
    try {
      await _client.channel(name)?.trigger(
            _eventController.text.trim(),
            _dataController.text,
          );
    } on PusherException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static bool _canTrigger(String name) =>
      name.startsWith('presence-') ||
      (name.startsWith('private-') && !name.startsWith('private-encrypted-'));

  @override
  Widget build(BuildContext context) {
    final state = _client.connectionState;
    final connected = state == 'CONNECTED';
    final channels = _client.channels.values.toList();
    final triggerable = channels.where((c) => _canTrigger(c.name)).toList();
    if (_triggerChannel != null &&
        !triggerable.any((c) => c.name == _triggerChannel)) {
      _triggerChannel = null;
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('pusher_client demo'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(widget.config.summary,
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Chip(
                  key: const Key('connection-state'),
                  avatar: Icon(Icons.circle,
                      size: 12,
                      color: connected ? Colors.green : scheme.outline),
                  label: Text(state),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Socket ID: ${_client.socketId ?? '-'}',
                    key: const Key('socket-id'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: const Key('connect'),
                  onPressed: () => _client.connect(),
                  child: const Text('Connect'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('disconnect'),
                  onPressed: () => _client.disconnect(),
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('channel-field'),
                    controller: _channelController,
                    decoration: const InputDecoration(
                      labelText: 'Channel name',
                      hintText: 'e.g. my-channel, private-x, presence-y',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _subscribe(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: const Key('subscribe'),
                  onPressed: _subscribe,
                  child: const Text('Subscribe'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (channels.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No subscribed channels.'),
              ),
            for (final channel in channels)
              _ChannelTile(
                channel: channel,
                onUnsubscribe: () => _unsubscribe(channel.name),
              ),
            const Divider(height: 32),
            Text('Trigger client event',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('trigger-channel'),
              initialValue: _triggerChannel,
              decoration: const InputDecoration(
                labelText: 'Private / presence channel',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in triggerable)
                  DropdownMenuItem(value: c.name, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _triggerChannel = v),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('event-field'),
              controller: _eventController,
              decoration: const InputDecoration(
                labelText: 'Event name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('data-field'),
              controller: _dataController,
              decoration: const InputDecoration(
                labelText: 'Data (JSON or text)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                key: const Key('trigger'),
                onPressed: _triggerChannel == null ? null : _trigger,
                child: const Text('Trigger'),
              ),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text('Event log (${_log.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  key: const Key('clear-log'),
                  onPressed: _log.isEmpty ? null : () => setState(_log.clear),
                  child: const Text('Clear'),
                ),
              ],
            ),
            if (_log.isEmpty) const Text('No events yet.'),
            for (final entry in _log)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${entry.event}'),
                subtitle: Text(
                  '${entry.timeText}  ${entry.channel ?? '-'}'
                  '${entry.userId == null ? '' : '  user ${entry.userId}'}\n'
                  '${entry.data ?? ''}',
                ),
                isThreeLine: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onUnsubscribe});

  final Channel channel;
  final VoidCallback onUnsubscribe;

  @override
  Widget build(BuildContext context) {
    final channel = this.channel;
    final members = channel is PresenceChannel ? channel.members : null;
    return Card(
      child: ListTile(
        title: Text(channel.name),
        subtitle: Text([
          channel.isSubscribed ? 'subscribed' : 'pending / failed',
          if (channel is PresenceChannel) 'me: ${channel.me ?? '-'}',
          if (members != null)
            'members (${members.length}): ${members.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
        ].join('\n')),
        isThreeLine: members != null,
        trailing: TextButton(
          onPressed: onUnsubscribe,
          child: const Text('Unsubscribe'),
        ),
      ),
    );
  }
}
