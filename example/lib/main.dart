import 'package:example/preview_image_printer.dart';
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

  List<Uint8List> productImages = [];

  final List<ProductBarcodeModel> products = [
    ProductBarcodeModel(
      barcode: "12345678",
      name: "Sản phẩm iPhone 16 Pro Max",
      price: "28.900.000 VNĐ",
      quantity: 3,
    ),
    ProductBarcodeModel(
      barcode: "56789345233",
      name: "Sản phẩm iPad Pro",
      price: "27.890.000 VNĐ",
      quantity: 2,
    )
  ];

  @override
  void initState() {
    super.initState();
    initConnectionListener();
  }

  Future<void> getListProd({
    TypePrintEnum? typePrintEnum,
  }) async {
    productImages = await captureProductListAsImages(
      products,
      context,
      typePrintEnum: typePrintEnum ?? TypePrintEnum.singleLabel,
    );
  }

  void initConnectionListener() {
    PrinterLabel.getConnectionStatus(
      (isConnected) {
        setState(
          () {
            widget.isConnectedUsb = isConnected;
          },
        );
      },
    );
  }

  Future<void> printProductLabels() async {
    final images = await captureProductListAsImages(
      products,
      context,
      typePrintEnum: TypePrintEnum.doubleLabel,
    );

    final totalQuantity =
        products.fold(0, (sum, product) => sum + product.quantity);

    for (var image in images) {
      final model = ImageModel(
        imageData: image,
        quantity: (totalQuantity / 2).ceil(),
        height: 25,
        x: 0,
        y: 5,
        width: 70,
      );
      await PrinterLabel.printImage(imageModel: model);
    }
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
              child: BarcodeView(
                product: ProductBarcodeModel(
                  barcode: "12345678",
                  name: "Sản phẩm iPhone 16 Pro Max",
                  price: "28.900.000 VNĐ",
                ),
                typePrintEnum: TypePrintEnum.singleLabel,
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
                _printTypeSingleLabel(),
                _printTypeDoubleLabel(),
              ],
            ),
            _viewListImage(),
          ],
        ),
      ),
    );
  }

  Widget _printTypeDoubleLabel() {
    return ElevatedButton(
      onPressed: () async {
        await printProductLabels();
      },
      child: Text(
        "Print(${products.map(
              (e) => e.quantity,
            ).reduce(
              (value, element) => value + element,
            )}) product 2 label",
      ),
    );
  }

  Widget _viewListImage() {
    return ElevatedButton(
      onPressed: () async {
        await getListProd(typePrintEnum: TypePrintEnum.doubleLabel);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ImageDisplayScreen(imageBytesList: productImages),
          ),
        );
      },
      child: Text(
        "View list( ${products.map(
              (e) => e.quantity,
            ).reduce(
              (value, element) => value + element,
            )})",
      ),
    );
  }

  Widget _printTypeSingleLabel() {
    return ElevatedButton(
      onPressed: () async {
        await getListProd();
        for (var i = 0; i < products.length; i++) {
          final ImageModel model = ImageModel(
            imageData: productImages[i],
            quantity: products[i].quantity,
            y: 20,
          );
          await PrinterLabel.printImage(imageModel: model);
        }
      },
      child: Text(
        "Print(${products.map(
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
          await PrinterLabel.printImage(imageModel: model);
        }
      },
      child: const Text(
        "Print list image local",
      ),
    );
  }
}
