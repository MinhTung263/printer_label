import 'package:example/select_size.dart';
import 'package:example/select_type_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      TextEditingController(text: "192.168.1.35");
  FocusNode focusNode = FocusNode();

  final List<ProductBarcodeModel> products = [];
  LabelPerRow _selectedRow = LabelPerRow.single;

  @override
  void initState() {
    super.initState();
    checkConnectPrint();
    addProducts();
  }

  void addProducts() {
    products.clear();
    products.addAll([
      ProductBarcodeModel(
        barcode: "83868888",
        name: "iPhone 17 Pro Max",
        price: 28990000,
        quantity: 5,
      ),
      // ProductBarcodeModel(
      //   barcode: "56782123931231",
      //   name: "iPad Pro",
      //   price: 34980000,
      //   quantity: 5,
      // ),
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

  Widget _buildBarcodeLabel(
    ProductBarcodeModel product,
    Dimensions dimensions,
  ) {
    return BarcodeView<ProductBarcodeModel>(
      data: product,
      dimensions: dimensions,
      nameBuilder: (p) => p.name,
      barcodeBuilder: (p) => p.barcode,
      priceBuilder: (p) => p.price,
    );
  }

  Future<void> generateLabelImages({
    required LabelPerRow labelPerRow,
  }) async {
    final images = await LabelFromWidget.captureImages<ProductBarcodeModel>(
      products,
      context,
      labelPerRow: labelPerRow,
      itemBuilder: _buildBarcodeLabel,
      quantity: (p) => p.quantity,
    );

    productImages
      ..clear()
      ..addAll(images);
  }

  Future<void> checkConnectPrint() async {
    final isConnected = await PrinterLabel.checkConnect();
    setState(() {
      widget.isConnected = isConnected;
    });
  }

  Future<void> printLabels() async {
    await LabelPrintService.instance.printLabels<ProductBarcodeModel>(
      items: products,
      context: context,
      labelPerRow: _selectedRow,
      itemBuilder: _buildBarcodeLabel,
      quantity: (p) => p.quantity,
    );
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

  Future<Uint8List> loadImageFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
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
              child: BarcodeView<ProductBarcodeModel>(
                data: products.first,
                nameBuilder: (p) => p.name,
                barcodeBuilder: (p) => p.barcode,
                priceBuilder: (p) => p.price,
              ),
            ),
            padding(),
            _buildPrintBarcode(),
            padding(),
            _buildPrintMultilLabel(),
            padding(),
            _viewListImage(),
            padding(),
            _viewCupSticker(),
            padding(),
            ElevatedButton(
              onPressed: () async {
                await generateLabelImages(
                  labelPerRow: LabelPerRow.single,
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
            padding(),
            _printCupSticket(),
            padding(),
            padding(),
          ],
        ),
      ),
    );
  }

  Widget padding() {
    return const Padding(padding: EdgeInsets.all(10));
  }

  Widget _buildPrintMultilLabel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        LabelPerRowSelector(
          initialValue: LabelPerRow.single,
          onChanged: (label) {
            setState(() {
              _selectedRow = label;
            });
          },
        ),
        ElevatedButton(
          onPressed: printLabels,
          child: const Text(
            "Print multi label",
          ),
        )
      ],
    );
  }

  Widget _printCupSticket() {
    return CupStickerSizeSelector(
      onPrint: (select) =>
          CupStickerPrintExample.printOrderCupSticker(select, context: context),
    );
  }

  Widget _buildButtonConnect() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Connect Status"),
        Container(
          padding: const EdgeInsets.all(8),
          color: widget.isConnected ? Colors.green : Colors.red,
          child: Text(
            widget.isConnected ? "Connect success" : "Connect false",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _viewListImage() {
    return ElevatedButton(
      onPressed: () async {
        addProducts();
        await generateLabelImages(
          labelPerRow: _selectedRow,
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

  Widget _viewCupSticker() {
    return ElevatedButton(
      onPressed: () async {
        final image = await LabelFromWidget.captureFromWidget(
          PreviewCupSticker(
            data: PreviewLabelModel(
              code: "1213",
              productName: "Trà sữa",
              price: "27.000 đ",
              companyName: "Printer Label",
              note: "Test print",
              labelIndex: 1,
              billDate: "01/01/2026",
              totalLabels: 1,
              toppings: ["Đá", "Đường"],
            ),
          ),
          context: context,
        );

        Navigator.push(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(
            builder: (context) => ImageDisplayScreen(imageBytesList: [image]),
          ),
        );
      },
      child: const Text(
        "View cup sticker",
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
