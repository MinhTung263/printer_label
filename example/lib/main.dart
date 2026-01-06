import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printer_label/enums/label_per_row_enum.dart';
import 'package:printer_label/src.dart';

import 'preview_image_printer.dart';

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
  bool isConnected = false;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String image1 = "images/image1.png";
  final String image2 = "images/image2.png";
  final String imageBarCode = "images/barcode.png";

  List<Uint8List> productImages = [];

  final TextEditingController textEditingController =
      TextEditingController(text: "192.168.1.46");
  FocusNode focusNode = FocusNode();

  final List<ProductBarcodeModel> products = [];

  @override
  void initState() {
    super.initState();
    checkConnectPrint();
    addProducts();
  }

  void addProducts() {
    products.clear();
    products.addAll([
      // ProductBarcodeModel(
      //   barcode: "83868888",
      //   name: "iPhone 17 Pro Max",
      //   price: 28990000,
      //   quantity: 2,
      // ),
      ProductBarcodeModel(
        barcode: "56782123931231",
        name: "iPad Pro",
        price: 34980000,
        quantity: 3,
      ),
      // ProductBarcodeModel(
      //   barcode: "56789345233",
      //   name: "Apple Pencil",
      //   price: 2350000,
      //   quantity: 2,
      // ),
      // ProductBarcodeModel(
      //   barcode: "1234543234",
      //   name: "MacBook Pro",
      //   price: 6589000,
      //   quantity: 3,
      // )
    ]);
  }

  Future<void> getListProd({
    required LabelPerRow labelPerRow,
    Dimensions? dimensions,
  }) async {
    final list = await captureProductListAsImages(
      products,
      context,
      labelPerRow: labelPerRow,
      dimensions: dimensions,
    );
    productImages.clear();
    productImages.addAll(list);
  }

  Future<void> checkConnectPrint() async {
    final isConnected = await PrinterLabel.checkConnect();
    setState(() {
      widget.isConnected = isConnected;
    });
  }

  Future<void> configPrintMultiLabel({
    required List<Uint8List> images,
  }) async {
    const LabelPerRow labelPerRow = LabelPerRow.three;

    await getListProd(
      labelPerRow: labelPerRow,
    );
    if (images.isNotEmpty) {
      final model = BarcodeImageModel(
        images: images,
        labelPerRow: labelPerRow,
      );
      await PrinterLabel.printLabel(barcodeImageModel: model);
    }
  }

  Future<void> connectLan() async {
    final input = textEditingController.text.replaceAll(',', '.');
    final bool connect = await PrinterLabel.connectLan(
      ipAddress: input,
    );
    setState(() {
      widget.isConnected = connect;
    });
    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Printer label"),
      ),
      body: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            padding(),
            _buildButtonConnect(),
            padding(),
            TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: const InputDecoration(
                hintText: 'Enter IP',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ), // nếu IP, nhập số và dấu .
            ),
            padding(),
            ElevatedButton(
              onPressed: () async => await connectLan(),
              child: const Text(
                "Connect Lan",
              ),
            ),
            const Padding(padding: EdgeInsets.all(10)),
            const Text("Print single label"),
            Card(
              elevation: 2,
              child: BarcodeView(
                product: products.first,
                labelColor: Colors.white,
              ),
            ),
            padding(),
            _viewListImage(),
            padding(),
            _buildPrintBarcode(),
            padding(),
            _printMultilLabel(),
            ElevatedButton(
              onPressed: () async {
                await getListProd(
                  labelPerRow: LabelPerRow.one,
                );
                await PrinterLabel.printThermal(
                    printThermalModel: PrintThermalModel(
                  image: productImages.first,
                ));
              },
              child: const Text(
                "Print thermal",
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget padding() {
    return const Padding(padding: EdgeInsets.all(10));
  }

  Widget _printMultilLabel() {
    return ElevatedButton(
      onPressed: () async {
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
        const Padding(padding: EdgeInsets.all(10)),
        InkWell(
          onTap: () async => await checkConnectPrint(),
          child: Container(
            padding: const EdgeInsets.all(8),
            color: widget.isConnected ? Colors.green : Colors.red,
            child: Text(
              widget.isConnected ? "Connect success" : "Connect",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _viewListImage() {
    return ElevatedButton(
      onPressed: () async {
        addProducts();
        await getListProd(
          labelPerRow: products.length == 1 ? LabelPerRow.one : LabelPerRow.two,
        );
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
