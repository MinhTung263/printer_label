import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printer_label/src.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter example printer',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: MyHomePage(),
    );
  }
}

// ignore: must_be_immutable
class MyHomePage extends StatefulWidget {
  MyHomePage({super.key});
  bool isConnectedUsb = false;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String image1 = "images/image1.png";
  final String image2 = "images/image2.png";
  final String imageBarCode = "images/barcode.png";

  Uint8List? uint8List;
  bool isShowPrint2Label = false;

  final List<Product> products = [
    Product(
      barcode: "12345678",
      name: "Sản phẩm iPhone 16 Pro Max",
      price: "28.900.000 VNĐ",
      quantity: 1,
    ),
    // Product(
    //   barcode: "56789345233",
    //   name: "Sản phẩm iPad Pro",
    //   price: "27.890.000 VNĐ",
    //   quantity: 1,
    // )
  ];

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
      body: SingleChildScrollView(
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(10)),
            _buildButtonConnect(),
            const Padding(padding: EdgeInsets.all(10)),
            const Text("Print single label"),
            Card(
              elevation: 2,
              child: ProductView(
                product: Product(
                  barcode: "12345678",
                  name: "Sản phẩm iPhone 16 Pro Max",
                  price: "28.900.000 VNĐ",
                ),
                typePrintEnum: TypePrintEnum.singleLabel,
              ),
            ),
            const Text("Print double label"),
            Card(
              elevation: 2,
              child: ProductView(
                product: Product(
                  barcode: "12345678",
                  name: "Sản phẩm iPhone 16 Pro Max",
                  price: "28.900.000 VNĐ",
                ),
                typePrintEnum: TypePrintEnum.doubleLabel,
              ),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            Row(
              children: [
                _printListImageLocal(),
                const Padding(padding: EdgeInsets.all(10)),
                _buildPrintBarcode(),
              ],
            ),
            const Padding(padding: EdgeInsets.all(10)),
            Row(
              children: [
                _viewCapture(),
                _printTypeSingleLabel(),
              ],
            ),
            _printTypeDoubleLabel(),
            const Padding(padding: EdgeInsets.all(10)),
            const Text("After screen shoot product"),
            if (uint8List != null) ...[
              Card(
                elevation: 2,
                child: Image.memory(uint8List!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _viewCapture() {
    return ElevatedButton(
      onPressed: () async {
        final List<Uint8List> productImages =
            await captureProductListAsImages(products, context);
        uint8List = productImages.first;
        setState(() {
          isShowPrint2Label = false;
        });
      },
      child: const Text(
        "View capture",
      ),
    );
  }

  Widget _printTypeDoubleLabel() {
    return ElevatedButton(
      onPressed: () async {
        final List<Uint8List> productImages = await captureProductListAsImages(
          products,
          context,
          typePrintEnum: TypePrintEnum.doubleLabel,
        );
        for (var i = 0; i < products.length; i++) {
          final ImageModel model = ImageModel(
            imageData: productImages[i],
            quantity: products[i].quantity,
            height: 25,
            x: 0,
            y: 5,
            width: 70,
          );
          await PrinterLabel.printImage(model: model);
        }
      },
      child: Text(
        "Print list( ${products.map(
              (e) => e.quantity,
            ).reduce(
              (value, element) => value + element,
            )}) product 2 label",
      ),
    );
  }

  Widget _printTypeSingleLabel() {
    return ElevatedButton(
      onPressed: () async {
        final List<Uint8List> productImages = await captureProductListAsImages(
          products,
          context,
          typePrintEnum: TypePrintEnum.singleLabel,
        );
        for (var i = 0; i < products.length; i++) {
          final ImageModel model = ImageModel(
            imageData: productImages[i],
            quantity: products[i].quantity,
            y: 20,
          );
          await PrinterLabel.printImage(model: model);
        }
      },
      child: Text(
        "Print list( ${products.map(
              (e) => e.quantity,
            ).reduce(
              (value, element) => value + element,
            )}) product",
      ),
    );
  }

  Widget _buildButtonConnect() {
    return Row(
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
              widget.isConnectedUsb ? "Connect USB success" : "Connect usb",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.all(10)),
        InkWell(
          onTap: () async {
            await PrinterLabel.connectLan(ipAddress: "192.168.50.91");
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            color: widget.isConnectedUsb ? Colors.green : Colors.red,
            child: Text(
              widget.isConnectedUsb ? "Connect Lan success" : "Connect lan",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrintBarcode() {
    return ElevatedButton(
      onPressed: () async {
        final List<TextData> textData = [
          TextData(
            y: 20,
            data: "Hello printer label",
          ),
          TextData(
            y: 170,
            data: "30.000",
          ),
          TextData(
            y: 200,
            data: "12345678",
          ),
        ];
        // Create an instance of PrintBarcodeModel
        final BarcodeModel printBarcodeModel = BarcodeModel(
          barcodeY: 60,
          width: 300,
          barcodeContent: "123456",
          textData: textData,
          quantity: 1,
        );
        await PrinterLabel.printBarcode(printBarcodeModel: printBarcodeModel);
      },
      child: const Text(
        "Print barcode",
      ),
    );
  }

  Widget _printListImageLocal() {
    return ElevatedButton(
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
            quantity: 2,
          );
          await PrinterLabel.printImage(model: model);
        }
      },
      child: const Text(
        "Print list image local",
      ),
    );
  }
}
