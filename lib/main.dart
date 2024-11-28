import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printer_label/src.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter example printer',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Label Printer flutter'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String image1 = "images/image1.png";
  String image2 = "images/image2.png";
  String imageBarCode = "images/barcode.png";
  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                await PrinterLabel.connectUSB();
              },
              child: const Text(
                "Connect usb",
              ),
            ),
            const Padding(padding: EdgeInsets.all(20)),
            ElevatedButton(
              onPressed: () async {
                final List<TextData> textData = [
                  TextData(
                    x: 0,
                    y: 10,
                    data: "Hello printer label",
                  ),
                  TextData(
                    x: 0,
                    y: 150,
                    data: "30.000",
                  ),
                  TextData(
                    x: 0,
                    y: 180,
                    data: "12345678",
                  ),
                ];
                // Create an instance of PrintBarcodeModel
                final BarcodeModel printBarcodeModel = BarcodeModel(
                  barcodeY: 50,
                  barcodeContent: "123456",
                  textData: textData,
                  quantity: 1,
                );
                await PrinterLabel.printBarcode(printBarcodeModel);
              },
              child: const Text(
                "Print barcode",
              ),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            Image.asset(image1),
            const Padding(padding: EdgeInsets.all(10)),
            ElevatedButton(
              onPressed: () async {
                final ByteData data = await rootBundle.load(image1);
                final Uint8List uint8List = data.buffer.asUint8List();
                final ImageModel model = ImageModel(
                  imageData: uint8List,
                  quantity: 1,
                );
                await PrinterLabel.printImage(model);
              },
              child: const Text(
                "Print image",
              ),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            ElevatedButton(
              onPressed: () async {
                // Load the images as byte data
                final List<Uint8List> imageDataList = [];
                // Example image paths (add your images here)
                final List<String> imagePaths = [
                  image1,
                  image2,
                  imageBarCode,
                ];

                // Load each image into Uint8List
                for (String imagePath in imagePaths) {
                  final ByteData data = await rootBundle.load(imagePath);
                  final Uint8List uint8List = data.buffer.asUint8List();
                  imageDataList.add(uint8List);
                }
                for (var i = 0; i < imageDataList.length; i++) {
                  final ImageModel model = ImageModel(
                    imageData: imageDataList[i],
                  );
                  await PrinterLabel.printImage(model);
                }
              },
              child: const Text(
                "Print list image",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
