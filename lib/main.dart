
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

import 'firebase_options.dart';

var logger = Logger(
  printer: PrettyPrinter(),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Flutter 엔진과 위젯 바인딩 초기화
  await Firebase.initializeApp( // Firebase 초기화
    options: DefaultFirebaseOptions.currentPlatform, // 플랫폼에 맞는 Firebase 설정 사용
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: TimeLogScreen(),
    );
  }
}

class TimeLogScreen extends StatefulWidget {
  const TimeLogScreen({super.key});

  @override
  _TimeLogScreenState createState() => _TimeLogScreenState();
}

class _TimeLogScreenState extends State<TimeLogScreen> {
  DateTime selectedDate = DateTime.now();
  List<LogItem> logItems = [];

  void _changeDate(bool forward) {
    setState(() {
      selectedDate = forward
          ? selectedDate.add(const Duration(days: 1))
          : selectedDate.subtract(const Duration(days: 1));
    });
  }

  Future<void> _addOrEdit(LogItem? item, TextEditingController textController) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    String documentId = DateFormat('yyyy-MM-dd').format(selectedDate);
    if (item != null) {
      // 기존 로그 항목 업데이트
      var docRef = firestore.collection('logs').doc(documentId);
      await firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(docRef);
        if (snapshot.exists) {
          var items = List.from(snapshot['items']);
          int index = items.indexWhere((i) => i['id'] == item.id);
          if (index != -1) {
            items[index] = {'id': item.id, 'content': textController.text, 'time': item.time, 'finish_time': item.finishTime};
            transaction.update(docRef, {'items': items});
          }
        }
      });
    } else {
      // 새 로그 항목 추가
      var newItem = {
        'id': const Uuid().v4(),
        'content': textController.text,
        'time': DateTime.now(),
      };
      await firestore.collection('logs').doc(documentId).set({
        'items': FieldValue.arrayUnion([newItem])
      }, SetOptions(merge: true));
    }
    Navigator.of(context).pop();
  }

  void _addOrEditLogItem({LogItem? item}) {
    TextEditingController textController = TextEditingController(text: item?.content ?? '');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(item == null ? 'Add Time Log' : 'Edit Time Log'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: "Fill the contents"),
            onSubmitted: (value) {
              _addOrEdit(item, textController);
            },
          ),
          actions: <Widget>[
            IconButton(
              icon: Image.asset('assets/images/check.png', scale: 20),
              onPressed: () => _addOrEdit(item, textController),
            ),
            IconButton(
              icon: Image.asset('assets/images/delete_bold.png', scale: 20),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _deleteLogItem(LogItem item, int index) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    String documentId = DateFormat('yyyy-MM-dd').format(selectedDate);
    var docRef = firestore.collection('logs').doc(documentId);

    await firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(docRef);
      if (!snapshot.exists) throw Exception("Document does not exist!");

      var items = List.from(snapshot['items'] as List);
      items.removeWhere((element) => element['id'] == item.id);

      if (items.isEmpty) {
        transaction.delete(docRef);
      } else {
        transaction.update(docRef, {'items': items});
      }
    }).then((value) {
      // 리스트가 비어있지 않고, 주어진 인덱스가 리스트 범위 내에 있는지 확인
      if (logItems.isNotEmpty && index >= 0 && index < logItems.length) {
        setState(() {
          logItems.removeAt(index);
        });
      }
    }).catchError((error, stacktrace) {
      logger.e("Error deleting item: $error");
      logger.e("stactrace: $stacktrace");
    });
  }

  void _finishLogItem(LogItem item) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    String documentId = DateFormat('yyyy-MM-dd').format(selectedDate);
    DateTime now = DateTime.now();
    var docRef = firestore.collection('logs').doc(documentId);
    await firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        var items = List.from(snapshot['items']);
        int index = items.indexWhere((i) => i['id'] == item.id);
        if (index != -1) {
          items[index] = {'id': item.id, 'content': item.content, 'time': item.time, 'finish_time': now};
          transaction.update(docRef, {'items': items});
        }
      }
    }).then((value) {
      setState(() {
        item.finishTime = now;
      });
    }).catchError((error, stacktrace) {
      logger.e("Error finishing item: $error");
      logger.e("stactrace: $stacktrace");
    });
  }

  String formatSubtitle(LogItem item) {
    final startTime = DateFormat('hh:mm a').format(item.time);
    if (item.finishTime != null) {
      final finishTime = DateFormat('hh:mm a').format(item.finishTime!);
      final duration = item.finishTime!.difference(item.time);
      final formattedDuration = "${duration.inHours}:${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}";
      return "$startTime ~ $finishTime, total: $formattedDuration";
    } else {
      return startTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Time Log',
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0, // Removes shadow from the app bar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1), // 그림자 색상
                  spreadRadius: 0.1, // 그림자 범위
                  blurRadius: 0.5, // 블러 효과
                  offset: Offset(0, 1), // 그림자 위치 조정
                ),
              ],
            ),
            height: 1.0,
          ),
        ),
        actions: <Widget>[
          IconButton(
            icon: Image.asset('assets/images/arrow_left.png', scale: 3),
            onPressed: () => _changeDate(false),
          ),
          Expanded( // Text wrapped with Expanded
            child: Center( // Center added for Text
              child: Text(
                DateFormat('yyyy-MM-dd').format(selectedDate),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 20,
                ), // Text color changed to black
              ),
            ),
          ),
          IconButton(
            icon: Image.asset('assets/images/arrow_right.png', scale: 3),
            onPressed: () => _changeDate(true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('logs').doc(DateFormat('yyyy-MM-dd').format(selectedDate)).snapshots(),
              builder: (context, AsyncSnapshot<DocumentSnapshot> snapshot) {
                if (snapshot.hasError) return Text('Error: ${snapshot.error}');
                switch (snapshot.connectionState) {
                  case ConnectionState.waiting:
                    return const Center(child: CircularProgressIndicator());
                  default:
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      // 문서가 존재하지 않는 경우
                      return const Center();
                    }

                    var docData = snapshot.data!.data() as Map<String, dynamic>;
                    List<LogItem> logItems = []; // 모든 로그 항목을 저장할 리스트

                    var items = docData.containsKey('items') ? List.from(docData['items'] as List<dynamic>) : [];

                    for (var itemData in items) {
                      logItems.add(LogItem.fromMap(itemData));
                    }

                    // 로그 항목이 없는 경우 빈 화면
                    if (logItems.isEmpty) {
                      return const Center();
                    }

                    // 로그 항목이 있는 경우
                    return ListView.builder(
                      itemCount: logItems.length,
                      itemBuilder: (context, index) {
                        final item = logItems[index];
                        // LogItem 객체를 사용하여 UI 구성
                        return Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.access_time, size: 35),
                              title: Text(
                                item.content,
                                style: const TextStyle(fontSize: 15),
                              ),
                              subtitle: Text(
                                formatSubtitle(item),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => _addOrEditLogItem(item: item),
                                    child: Container(
                                      width: 25,
                                      height: 25,
                                      color: Colors.transparent,
                                      child: Center(
                                        child: Image.asset('assets/images/edit.png', width: 25, height: 25),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  GestureDetector( // 커스텀 버튼(버튼 실제 크기 커스텀)
                                    onTap: () => _finishLogItem(item),
                                    child: Container(
                                      // 버튼 크기 지정
                                      width: 25,
                                      height: 25,
                                      color: Colors.transparent,
                                      child: Center(
                                        child: Image.asset('assets/images/check.png', width: 25, height: 25),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10), // 빈 공간
                                  GestureDetector(
                                    onTap: () => _deleteLogItem(item, index),
                                    child: Container(
                                      width: 25,
                                      height: 25,
                                      color: Colors.transparent,
                                      child: Center(
                                        child: Image.asset('assets/images/delete.png', width: 25, height: 25),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              dense: true, // 더 조밀한 레이아웃 적용
                            ),
                            Container(
                              color: Colors.grey[300],
                              height: 1.0,
                            ),
                          ],
                        );
                      },
                    );
                }
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 75.0,
        width: double.infinity, // Container를 부모의 가로 크기에 맞게 확장
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bar_bottom.png'),
            fit: BoxFit.cover, // 이미지가 컨테이너를 꽉 채우도록 조정
          ),
        ),
        child: ElevatedButton(
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                if (states.contains(MaterialState.pressed)) { // 버튼이 눌렸을 때
                  return Colors.grey; // 회색으로 변경
                }
                return Colors.transparent; // 그 외 상태에서는 투명
              },
            ),
            shape: MaterialStateProperty.all<RoundedRectangleBorder>( // 모서리를 직사각형으로 설정
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          child: const Text('Add Time Log', style: TextStyle(fontSize: 25, color: Colors.white)),
          onPressed: () => _addOrEditLogItem(),
        ),
      ),
    );
  }

}

class LogItem {
  String id; // 고유 ID
  String content; // 내용
  DateTime time; // 시작 시간
  DateTime? finishTime; // 완료 시간

  LogItem({required this.id, required this.content, required this.time, this.finishTime});

  // Firestore 문서의 데이터로부터 LogItem 객체를 생성하는 팩토리 생성자
  factory LogItem.fromMap(Map<String, dynamic> data) {
    return LogItem(
      id: data['id'],
      content: data['content'],
      time: (data['time'] as Timestamp).toDate(),
      finishTime: data['finish_time'] != null ? (data['finish_time'] as Timestamp).toDate() : null,
    );
  }

  // LogItem 객체를 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'time': time,
      'finish_time': finishTime,
    };
  }
}
