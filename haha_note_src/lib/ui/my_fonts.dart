import 'package:cloud_disk_note_app/util/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cloud_disk_note/app.dart';

const _TAG = "my_fonts.dart";

String? myFontMono;
String? myFontRegular;
List<String>? myFontFallbacksForMono;

Future<void> initFonts() async {
  try {
    myFontMono = "AppMono";
    final fontLoaderMono = FontLoader(myFontMono!);
    fontLoaderMono.addFont(rootBundle.load('assets/fonts/JetBrainsMonoNL-Regular.ttf'));
    await fontLoaderMono.load();

    if(!isPcPlatform()) {
      return;
    }

    myFontRegular = "AppRegular";
    final fontLoaderRegular = FontLoader(myFontRegular!);
    fontLoaderRegular.addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
    await fontLoaderRegular.load();

    myFontFallbacksForMono = [myFontRegular!];
  } catch (e, st) {
    myFontMono = null;
    myFontRegular = null;
    App.logger.debug(_TAG, "load font failed: $e\n$st");
  }
}

extension MonoTextStyle on TextStyle {
  // usage: TextStyle(...).toMono()
  TextStyle toMono() => copyWith(
    fontFamily: myFontMono,
    fontFamilyFallback: myFontFallbacksForMono,
  );
}
