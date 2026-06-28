import 'package:flutter/material.dart' show Widget, Card, EdgeInsets, BorderRadius, RoundedRectangleBorder, Padding, EdgeInsetsGeometry;

Widget getCard({required Widget child}) {
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6.0),
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    child: Padding(
      padding: EdgeInsetsGeometry.all(10),
      child: child
    ),
  );
}
