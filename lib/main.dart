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
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({super.key});
  bool isConnectedUsb = false;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String image1 = "images/image1.png";
  String image2 = "images/image2.png";
  String imageBarCode = "images/barcode.png";

  @override
  void initState() {
    super.initState();
    initConnectionListener();
  }

  void initConnectionListener() {
    PrinterLabel.setupConnectionStatusListener(
      (isConnected) {
        setState(
          () {
            widget.isConnectedUsb = isConnected;
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Printer label"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: () async {
                await PrinterLabel.connectUSB();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                color: widget.isConnectedUsb ? Colors.green : Colors.blue,
                child: Text(
                  widget.isConnectedUsb ? "Connect success" : "Connect usb",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.all(20)),
            InkWell(
              onTap: () async {
                await PrinterLabel.connectLan(ipAddress: "");
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                color: widget.isConnectedUsb ? Colors.green : Colors.blue,
                child: Text(
                  widget.isConnectedUsb ? "Connect success" : "Connect lan",
                  style: const TextStyle(color: Colors.white),
                ),
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
                await PrinterLabel.printBarcode(
                    printBarcodeModel: printBarcodeModel);
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
                await PrinterLabel.printImage(model: model);
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
                  await PrinterLabel.printImage(model: model);
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
