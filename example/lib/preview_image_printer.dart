import 'dart:typed_data';

import 'package:flutter/material.dart';

class ImageDisplayScreen extends StatelessWidget {
  final List<Uint8List> imageBytesList;

  const ImageDisplayScreen({super.key, required this.imageBytesList});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Captured Images"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: imageBytesList.map((imageBytes) {
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.memory(
                imageBytes,
                filterQuality: FilterQuality.high,
              ), // Display each image
            );
          }).toList(),
        ),
      ),
    );
  }
}
