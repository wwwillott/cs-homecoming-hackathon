import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectOrbitWebSocket(Uri uri) =>
    IOWebSocketChannel.connect(uri);
