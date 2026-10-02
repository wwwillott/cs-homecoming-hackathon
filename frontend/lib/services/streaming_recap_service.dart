import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/contact.dart';
import 'recap_service.dart';

class ApiRecapService implements RecapService {
  ApiRecapService({
    String apiUrl = const String.fromEnvironment(
      'ORBIT_API_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    this._userId,
    AudioRecorder? recorder,
    http.Client? client,
  }) : _apiUri = Uri.parse(apiUrl),
       _recorder = recorder ?? AudioRecorder(),
       _client = client ?? http.Client();

  static const _maxBufferedChunks = 600;
  static const _chunkBytes = 3200;

  final Uri _apiUri;
  final String? Function()? _userId;
  final AudioRecorder _recorder;
  final http.Client _client;
  final _progress = StreamController<RecapProgress>.broadcast();
  final Map<int, Uint8List> _pending = {};
  final Map<int, Uint8List> _recentAcknowledged = {};
  final List<int> _carry = [];

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Completer<void>? _ready;
  Completer<void>? _complete;
  RecapKind _kind = RecapKind.recap;
  String _committed = '';
  String _interim = '';
  String? _sessionId;
  int _sequence = 0;
  int _droppedChunks = 0;
  bool _active = false;
  bool _stopping = false;
  bool _socketReady = false;

  @override
  Stream<RecapProgress> get progress => _progress.stream;

  Uri get _webSocketUri {
    final scheme = _apiUri.scheme == 'https' ? 'wss' : 'ws';
    final id = _userId?.call();
    return _apiUri.replace(
      scheme: scheme,
      path: '/api/transcriptions/stream',
      queryParameters: id == null || id.isEmpty ? const {} : {'user_id': id},
      fragment: null,
    );
  }

  Uri _api(String path) =>
      _apiUri.replace(path: path, query: null, fragment: null);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_userId?.call() case final id? when id.isNotEmpty) 'X-User-Id': id,
      };

  @override
  Future<void> start({required RecapKind kind}) async {
    await cancel();
    if (!await _recorder.hasPermission()) {
      throw StateError(
        'Microphone permission is required to record a conversation.',
      );
    }
    _kind = kind;
    _active = true;
    _stopping = false;
    _committed = '';
    _interim = '';
    _sessionId = null;
    _sequence = 0;
    _droppedChunks = 0;
    _pending.clear();
    _recentAcknowledged.clear();
    _carry.clear();
    _complete = Completer<void>();
    await _connect();

    final audio = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _audioSubscription = audio.listen(
      _acceptAudio,
      onError: (Object error) => _emit(message: 'Microphone error: $error'),
    );
  }

  Future<void> _connect() async {
    if (!_active) return;
    _socketReady = false;
    _ready = Completer<void>();
    final channel = WebSocketChannel.connect(_webSocketUri);
    _channel = channel;
    _socketSubscription = channel.stream.listen(
      (message) => _handleSocketMessage(channel, message),
      onError: (Object error) => _handleSocketClosed(channel, error),
      onDone: () => _handleSocketClosed(channel),
      cancelOnError: true,
    );
    await channel.ready;
    channel.sink.add(
      jsonEncode({
        'type': 'start',
        if (_sessionId != null) 'session_id': _sessionId,
      }),
    );
    await _ready!.future.timeout(const Duration(seconds: 10));
  }

  void _handleSocketMessage(WebSocketChannel source, dynamic message) {
    if (!identical(source, _channel) || message is! String) return;
    final event = jsonDecode(message) as Map<String, dynamic>;
    switch (event['type']) {
      case 'ready':
        _socketReady = true;
        _sessionId = event['session_id'] as String?;
        final restored = event['text'] as String? ?? '';
        if (restored.isNotEmpty) _committed = restored;
        for (final entry in _recentAcknowledged.entries) {
          _sendFrame(entry.key, entry.value);
        }
        for (final entry in _pending.entries) {
          _sendFrame(entry.key, entry.value);
        }
        if (_droppedChunks > 0) {
          _sendGap();
        }
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
        _emit(message: 'Live transcription connected');
        break;
      case 'ack':
        final sequence = event['sequence'] as int?;
        if (sequence != null) {
          final acknowledged = _pending.remove(sequence);
          if (acknowledged != null) {
            _recentAcknowledged[sequence] = acknowledged;
            while (_recentAcknowledged.length > 10) {
              _recentAcknowledged.remove(_recentAcknowledged.keys.first);
            }
          }
        }
        break;
      case 'interim':
        _interim = event['text'] as String? ?? '';
        _emit();
        break;
      case 'final':
        final text = (event['text'] as String? ?? '').trim();
        if (text.isNotEmpty) _committed = '$_committed $text'.trim();
        _interim = '';
        _emit();
        break;
      case 'reconnecting':
        _emit(
          message: event['message'] as String? ?? 'Refreshing speech stream…',
        );
        break;
      case 'gap':
        _emit(
          message:
              event['message'] as String? ??
              'Some audio could not be recovered.',
          hasGap: true,
        );
        break;
      case 'error':
        _emit(message: event['message'] as String? ?? 'Transcription failed.');
        break;
      case 'complete':
        if (!(_complete?.isCompleted ?? true)) _complete!.complete();
        break;
    }
  }

  void _handleSocketClosed(WebSocketChannel source, [Object? error]) {
    if (!identical(source, _channel)) return;
    _socketReady = false;
    if (!_active || _stopping) return;
    _emit(message: 'Connection lost. Buffering audio and reconnecting…');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 1), () {
      _connect().catchError((Object reconnectError) {
        _handleSocketClosed(source, reconnectError);
      });
    });
  }

  void _acceptAudio(Uint8List bytes) {
    if (!_active) return;
    _carry.addAll(bytes);
    while (_carry.length >= _chunkBytes) {
      final pcm = Uint8List.fromList(_carry.sublist(0, _chunkBytes));
      _carry.removeRange(0, _chunkBytes);
      _queueChunk(pcm);
    }
  }

  void _queueChunk(Uint8List pcm) {
    final sequence = _sequence++;
    _pending[sequence] = pcm;
    while (_pending.length > _maxBufferedChunks) {
      _pending.remove(_pending.keys.first);
      _droppedChunks++;
      _emit(
        message:
            'The reconnect buffer filled; part of the conversation was lost.',
        hasGap: true,
      );
    }
    if (_socketReady) _sendFrame(sequence, pcm);
  }

  void _sendFrame(int sequence, Uint8List pcm) {
    if (!_socketReady) return;
    final data = ByteData(4 + pcm.length)
      ..setUint32(0, sequence, Endian.little);
    data.buffer.asUint8List(4).setAll(0, pcm);
    _channel?.sink.add(data.buffer.asUint8List());
  }

  void _sendGap() {
    if (!_socketReady || _droppedChunks == 0) return;
    _channel?.sink.add(jsonEncode({'type': 'gap', 'count': _droppedChunks}));
    _droppedChunks = 0;
  }

  void _emit({String? message, bool hasGap = false}) {
    if (_progress.isClosed) return;
    _progress.add(
      RecapProgress(
        committedTranscript: _committed,
        interimTranscript: _interim,
        message: message,
        hasGap: hasGap,
      ),
    );
  }

  @override
  Future<RecapDraft> stopAndSummarize() async {
    if (!_active || _sessionId == null) {
      throw StateError('No live transcription session is active.');
    }
    _stopping = true;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    if (_carry.length >= 2) {
      final evenLength = _carry.length - _carry.length.remainder(2);
      _queueChunk(Uint8List.fromList(_carry.sublist(0, evenLength)));
      _carry.clear();
    }
    _sendGap();
    _channel?.sink.add(jsonEncode({'type': 'stop'}));
    await _complete!.future.timeout(const Duration(seconds: 15));
    final sessionId = _sessionId!;
    _active = false;
    await _closeSocket();

    final response = await _client.post(
      _api('/api/transcription-sessions/$sessionId/draft'),
      headers: _headers,
      body: jsonEncode({'kind': _kind.name}),
    );
    final body = _jsonBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_apiError(body, response.statusCode));
    }
    return RecapDraft.fromJson(body);
  }

  @override
  Future<Contact> commitDraft({
    required RecapDraft draft,
    required Contact contact,
  }) async {
    if (draft.sessionId == null) return contact;
    final response = await _client.post(
      _api('/api/transcription-sessions/${draft.sessionId}/commit'),
      headers: _headers,
      body: jsonEncode({'contact': contact.toJson()}),
    );
    final body = _jsonBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_apiError(body, response.statusCode));
    }
    return contact.copyWith(id: body['person_id'] as String);
  }

  Map<String, dynamic> _jsonBody(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      return {};
    }
  }

  String _apiError(Map<String, dynamic> body, int status) =>
      body['detail'] as String? ??
      'Backend request failed with status $status.';

  @override
  Future<RecapDraft> summarize({
    required Uint8List audio,
    required String mimeType,
    required RecapKind kind,
  }) => throw UnsupportedError('Use live streaming transcription.');

  @override
  Future<void> cancel() async {
    _active = false;
    _stopping = true;
    _reconnectTimer?.cancel();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    await _closeSocket();
  }

  Future<void> _closeSocket() async {
    _socketReady = false;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
    _client.close();
    await _progress.close();
  }
}
