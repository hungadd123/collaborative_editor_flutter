import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill_delta_from_html/parser/html_to_delta.dart';
import 'package:http/http.dart' as http;
//Web
import 'package:web_socket_channel/web_socket_channel.dart'
  if (dart.library.html) 'package:web_socket_channel/html.dart'
  if (dart.library.io) 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
class CollabEditor extends StatefulWidget {
  final String documentId;
  final String userId;
  const CollabEditor({super.key , required this.documentId,required this.userId});

  @override
  State<CollabEditor> createState() => _CollabEditorState();
}

class _CollabEditorState extends State<CollabEditor> {
  late final QuillController _controller;
  late final WebSocketChannel _channel;
  Timer? _autosaveTimer;
  int _version = 1; // Track local version
  bool _hasSend = false;

  @override
  void initState() {
    super.initState();
    final wsUrl = getWebSocketUrl();
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    final doc = Document();
    _controller = QuillController(
        document: doc, selection: const TextSelection.collapsed(offset: 0));

    _loadInitialContent();

    _channel.stream.listen((message) {
      print("🟢 Received from server: $message");
      try {
        // Check message type
        final data = message is String
            ? jsonDecode(message)
            : jsonDecode(utf8.decode(message));
          if (data['type'] == 'delta_update' && data['document_id'] == widget.documentId) {
            final delta = Delta.fromJson(data['delta']);
            _controller.compose(delta, _controller.selection, ChangeSource.remote);
            //print("🔁 Applying delta: $delta");
            //print("Current selection: ${_controller.selection}");
          } else if (data['type'] == 'version_update') {
            if (/*data['user_id'] != widget.userId && */data['document_id'] == widget.documentId) {
              setState(() {
                _version = data['version_number'];
              });
              //print('Received new version: $_version from user ${data['user_id']}');
            }
          }
      } catch (e) {
        print("Error processing message: $e");
      }
    });
//=====================
    //Add event listener Typing
    _controller.document.changes.listen((event) {
      if (event.source == ChangeSource.local) {
        final delta = event.change;
        final message = jsonEncode({
          'type': 'delta_update',
          'document_id': widget.documentId,
          'user_id': widget.userId,
          'delta': delta.toJson(),
        });
        _channel.sink.add(message);
        print(message);
        if (!_hasSend) {
          _hasSend = true;
          _sendEditNotification(widget.userId,widget.documentId);
        }
        _scheduleAutoSave();
      }
    });
  }

  String getWebSocketUrl() {
    if (kIsWeb) {
      return 'ws://192.168.1.16:8081'; // IP local
    } else if (Platform.isAndroid) {
      return 'ws://192.168.1.16:8081'; // IP local
    } else {
      return 'ws://localhost:8081';
    }
  }
    Future<void> _loadInitialContent() async {
    final res = await http.get(Uri.parse('https://p6qgt0wlh4.execute-api.ap-southeast-1.amazonaws.com/dev/documents/${widget.documentId}'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _version = data['version_number'] ?? 1;
      final htmlContent = data['content'] ?? '';
      //print('HTML: $htmlContent' );
      final cleanedHtml = htmlContent.replaceAllMapped(
        RegExp(r'</p><p>'),
            (match) => '</p><p>\n',
      ).replaceAll('</p>', '</p>\n');
      //print('CleanedHTML: $cleanedHtml');
      // Convert HTML -> Delta JSON
      final converter = HtmlToDelta().convert(cleanedHtml);
      //print('Delta: $converter');
      final document = Document.fromDelta(converter);
      setState(() {
        _version = data['version_number'];
        _controller.compose(
          document.toDelta(),
          _controller.selection,
          ChangeSource.remote,
        );
      });
    }
  }

  String deltaToHtml(Delta delta) {
    final buffer = StringBuffer();

    for (final op in delta.toList()) {
      if (op.key == 'insert') {
        final value = op.value;
        final attributes = op.attributes ?? {};

        if (value is String) {
          final lines = value.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.isEmpty && i == lines.length - 1) continue;

            var formattedLine = line;

            // Add format
            if (attributes.containsKey('bold')) {
              formattedLine = '<strong>$formattedLine</strong>';
            }
            if (attributes.containsKey('italic')) {
              formattedLine = '<em>$formattedLine</em>';
            }

            buffer.writeln('<p>$formattedLine</p>');
          }
        }
      }
    }

    return buffer.toString();
  }

  void _scheduleAutoSave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), _saveDocument);
  }

  Future<void> _saveDocument() async {

    final content = _controller.document.toDelta();
    final htmlContent = deltaToHtml(content);
    //final contentJson = jsonEncode(htmlContent);
    final uri = Uri.parse("https://p6qgt0wlh4.execute-api.ap-southeast-1.amazonaws.com/dev/documents/${widget.documentId}/autosave");

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "content": htmlContent,
        "version_number": _version,
        "user_id": widget.userId,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      _version = body['version_number'];
      print("Document saved, version: $_version");

      _channel.sink.add(jsonEncode({
        'type': 'version_update',
        'document_id': widget.documentId,
        'version_number': _version,
        'user_id': widget.userId,
      }));
    } else if (response.statusCode == 409) {
      final conflict = jsonDecode(response.body);
      _showConflictDialog(conflict['latest_version']);
    } else {
      print("Failed to save document: ${response.body}");
    }
  }

  void _showConflictDialog(dynamic latestVersion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Conflict Detected"),
        content: const Text("A newer version of the document exists. Overwrite or reload?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _controller.document = Document.fromJson(jsonDecode(latestVersion['content']));
              _version = latestVersion['version_number'];
            },
            child: const Text("Reload"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              _version = latestVersion['version_number'];
              await _saveDocument();
            },
            child: const Text("Overwrite"),
          )
        ],
      ),
    );
  }
  Future<void> _sendEditNotification(String editor, String documentId) async {
    final uri = Uri.parse('https://qidsrvq581.execute-api.ap-southeast-1.amazonaws.com/dev/send_edit_notification');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'editor': editor,
        'documentId': documentId,
      }),
    );

    if (response.statusCode == 200) {
      print('✅ Email đã được gửi!');
    } else {
      print('❌ Thất bại: ${response.body}');
    }
  }

  @override
  void dispose() {
    _channel.sink.close();
    _controller.dispose();
    _autosaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Collaborative Editor')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            QuillSimpleToolbar(configurations: QuillSimpleToolbarConfigurations(controller: _controller)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all()),
                child: QuillEditor.basic(
                  configurations: QuillEditorConfigurations(
                    controller: _controller,
                    placeholder: 'Nhập nội dung tại đây...',
                    padding: const EdgeInsets.all(8),
                    sharedConfigurations: const QuillSharedConfigurations(locale: Locale('en')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
