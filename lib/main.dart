import 'package:flutter/material.dart';
import 'package:flutter_quill_collab_editor/widgets/collab_editor.dart';


void main() {
  runApp( const MaterialApp(home: CollabEditor(documentId: '1234', userId: '123',),),
  );
}
