
import 'package:cloud_disk_note_app/main.dart';
import 'package:flutter/material.dart';


const appIconSizeMid = AppIcon(size: 100);
const appIconSizeSmall = AppIcon(size: 72);

class AppIcon extends StatelessWidget {
  final double size;
  const AppIcon({super.key, this.size = 100});


  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        appIconPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

// 在登录和注册页面，在主视觉区域显示图标
List<Widget> getAppIconForMainView() {
  final list = <Widget>[];
  list.add(const SizedBox(height: 80));
  list.add(appIconSizeMid);
  list.add(const SizedBox(height: 60));

  return list;
}
