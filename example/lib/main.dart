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
      barcode: "83868888",
      name: "Sản phẩm iPhone 16 Pro Max",
      price: 28990000,
      quantity: 2,
    ),
    // ProductBarcodeModel(
    //   barcode: "56789345233",
    //   name: "Sản phẩm iPad Pro",
    //   price: 27890000,
    //   quantity: 2,
    // ),
    // ProductBarcodeModel(
    //   barcode: "1234543234",
    //   name: "Áo phông",
    //   price: 350000,
    //   quantity: 3,
    // )
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

  Future<void> configPrintImage({
    required List<Uint8List> images,
    required List<ProductBarcodeModel> products,
    required TypePrintEnum typePrint,
  }) async {
    final isPrintSigle = typePrint == TypePrintEnum.singleLabel;

    final List<Map<String, dynamic>> productList = [];
    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      final imageBytes = images[i];
      final model = BarcodeImageModel(
        imageData: imageBytes,
        quantity: product.quantity.toInt(),
        y: isPrintSigle ? 20 : 5,
        width: isPrintSigle ? null : 70,
        height: isPrintSigle ? null : 25,
      );
      productList.add(model.toMap());
    }
    await PrinterLabel.printImage(productList: productList);
  }

  Future<void> configPrintMultiLabel({
    required List<Uint8List> images,
  }) async {
    final model = BarcodeImageModel(
      y: 5,
      x: 10,
      images: images,
      width: 70,
      height: 25,
    );
    await PrinterLabel.printMultiLabel(barcodeImageModel: model);
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
                product: products.first,
                typePrintEnum: TypePrintEnum.singleLabel,
              ),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            _buildPrintBarcode(),
            const Padding(padding: EdgeInsets.all(10)),
            _printImage(
              typePrintEnum: TypePrintEnum.singleLabel,
            ),
            _printMultilLabel(),
            _viewListImage(),
            ElevatedButton(
              onPressed: () async {
                await getListProd();

                await PrinterLabel.printThermal(
                    printThermalModel: PrintThermalModel(
                  image: productImages.first,
                ));
              },
              child: const Text(
                "Print thermal",
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _viewListImage() {
    return ElevatedButton(
      onPressed: () async {
        await getListProd(typePrintEnum: TypePrintEnum.doubleLabel);
        Navigator.push(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(
            builder: (context) =>
                ImageDisplayScreen(imageBytesList: productImages),
          ),
        );
      },
      child: Text(
        "View list( ${products.map(
              (e) => e.quantity.toDouble(),
            ).reduce(
              (value, element) => value + element,
            )})",
      ),
    );
  }

  Widget _printImage({
    required TypePrintEnum typePrintEnum,
  }) {
    return ElevatedButton(
      onPressed: () async {
        await getListProd(
          typePrintEnum: typePrintEnum,
        );
        await configPrintImage(
          products: products,
          images: productImages,
          typePrint: typePrintEnum,
        );
      },
      child: Text(
        "Print ${typePrintEnum.name} (${products.map(
              (e) => e.quantity.toInt(),
            ).reduce(
              (value, element) => value + element,
            )}) product",
      ),
    );
  }

  Widget _printMultilLabel() {
    return ElevatedButton(
      onPressed: () async {
        await getListProd(
          typePrintEnum: TypePrintEnum.doubleLabel,
        );
        await configPrintMultiLabel(
          images: productImages,
        );
      },
      child: Text(
        "Print multi label (${products.map(
              (e) => e.quantity.toInt(),
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
}
