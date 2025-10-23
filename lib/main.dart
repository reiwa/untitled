import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:test_project/RoomFinderApp.dart';
import 'package:test_project/RoomFinderAppEditor.dart';
import 'package:test_project/RoomFinderAppShared.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => BDataContainer('全学講義棟1号館', 2, 'zenkou', List.empty(), List.empty()),
      child: const MyApp(),
    ),
  );
}

class RoomFinder extends StatefulWidget {
  const RoomFinder({super.key});

  @override
  State<RoomFinder> createState() => _RoomFinderState();
}

enum CustomViewType { editor, finder }

class _RoomFinderState extends State<RoomFinder> {
  CustomView currentView = new EditorView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<CustomViewType>(
            onSelected: (type) {
              setState(() {
                currentView = type == CustomViewType.editor
                    ? const EditorView()
                    : const FinderView();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: CustomViewType.editor,
                child: Text('Editor'),
              ),
              const PopupMenuItem(
                value: CustomViewType.finder,
                child: Text('Finder'),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: Container(
          width: 360,
          height: 600,
          color: Colors.grey[200],
          child: currentView,
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  bool _isMessageVisible = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hello Flutter',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Hello Flutter'),
        ),
        body: Center(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[

              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text(
                    'Hello World!',
                    style: TextStyle(fontSize: 24),
                  ),

                  ElevatedButton(
                    child: const Text('RoomFinder'),

                    onPressed: () {

                      setState(() {
                        _isMessageVisible = true;
                      });
                    },
                  ),
                ],
              ),

              _isMessageVisible ? const RoomFinder() : Container(),

            ],
          ),
        ),
      ),
    );
  }
}