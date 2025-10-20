import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class RoomFinder extends StatefulWidget {
  const RoomFinder({super.key});

  @override
  State<RoomFinder> createState() => _RoomFinderState();
}

enum placeType {
  room,
  passage,
  elevator,
}

class _RoomFinderState extends State<RoomFinder> {
  Offset? _tapPosition;
  placeType currentType = placeType.room;

  final TransformationController _transformationController = TransformationController();

  final double _minScale = 0.3;
  final double _maxScale = 3.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300.0,
      height: 600.0,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            child: Row(
              children: <Widget>[
                ElevatedButton(
                  child: const Text('部屋'),

                  onPressed: () {

                    setState(() {
                      currentType = placeType.room;
                    });
                  },
                ),

                ElevatedButton(
                  child: const Text('廊下'),

                  onPressed: () {

                    setState(() {
                      currentType = placeType.passage;
                    });
                  },
                ),

                ElevatedButton(
                  child: const Text('階段・エレベーター'),

                  onPressed: () {

                    setState(() {
                      currentType = placeType.elevator;
                    });
                  },
                ),
              ],
            ),
          ),

          Container(
            height: 450,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black45, width: 1.0),
            ),
            clipBehavior: Clip.hardEdge,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: _minScale,
              maxScale: _maxScale,
              boundaryMargin: EdgeInsets.all(double.infinity),

              child: GestureDetector(
                onTapDown: (details) {
                  setState(() {
                    _tapPosition = details.localPosition;
                  });
                },
                child: Image.asset(
                  'assets/images/zenkou_1f.png',
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          if (_tapPosition != null)
            SelectableText(
              'position": { "x": \n${_tapPosition!.dx.toStringAsFixed(0)}, "y": ${_tapPosition!.dy.toStringAsFixed(0)} }\n"type": "${currentType.toString()}"',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            )
          else
            const Text(
              '画像をタップして座標を取得',
              style: TextStyle(fontSize: 12),
            ),

        ],
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