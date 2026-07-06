import 'package:hahanote_app/i18n/strings.g.dart' show t;
import 'package:hahanote_app/main.dart';
import 'package:hahanote_app/util/util.dart' show openUrlOrShowErrMsg, openEmailOrShowErrMsg;
import 'package:hahanote_app/widget/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../ui/ui.dart';

class AboutPage extends StatefulWidget {
  final String appName;
  final String appDesc;
  final String appIconAsset; // 本地资源路径，例如 "assets/icon.png"
  final String authorEmail; // 例如 "author@example.com"
  final String projectUrl; // 例如 "https://github.com/your/repo"
  final String privacyPolicyUrl;
  final String authorUrl;
  final String reportBugUrl;
  final String updateUrl;
  final void Function(String) showMsg;

  const AboutPage({
    super.key,
    required this.appName,
    required this.appDesc,
    required this.appIconAsset,
    required this.authorEmail,
    required this.projectUrl,
    required this.privacyPolicyUrl,
    required this.authorUrl,
    required this.reportBugUrl,
    required this.updateUrl,
    required this.showMsg,
  });

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _version = "${info.version} ${info.buildNumber.isNotEmpty ? "(${info.buildNumber})" : ""}";
      });
    } catch (e) {
      // 忽略错误，保持版本为空
    }
  }

  Future<void> _launchEmail(String email) async {
    await openEmailOrShowErrMsg(url: email, showMsg: widget.showMsg);
  }

  Future<void> _launchUrl(String urlStr) async {
    await openUrlOrShowErrMsg(url: urlStr, showMsg: widget.showMsg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 0, horizontal: UI.defaultScreenPadding),
      children: [
        const SizedBox(height: 16),

        Column(
          children: [
            // 应用图标与名称
            Wrap(
              children: [
                appIconSizeSmall,
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      widget.appName,
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _version.isNotEmpty ? _version : t.loading,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              children: [
                SelectableText(t.appDesc, style: TextStyle(fontSize: 18)),
              ],
            ),
            const SizedBox(height: 24),

            const Divider(),
          ],
        ),

        ListTile(
          leading: const Icon(Icons.home),
          title: Text(t.home),
          subtitle: Text(widget.projectUrl),
          onTap: () => _launchUrl(widget.projectUrl),
        ),

        ListTile(
          leading: const Icon(Icons.update),
          title: Text(t.update),
          subtitle: Text(widget.updateUrl),
          onTap: () => _launchUrl(widget.updateUrl),
        ),

        // ListTile(
        //   leading: const Icon(Icons.shopping_cart),
        //   title: Text(t.buy),
        //   subtitle: Text(buyVipUrl),
        //   onTap: () => _launchUrl(buyVipUrl),
        // ),

        ListTile(
          leading: const Icon(Icons.monetization_on),
          title: Text(t.donate),
          subtitle: Text(donateUrl),
          onTap: () => _launchUrl(donateUrl),
        ),

        ListTile(
          leading: const Icon(Icons.person),
          title: Text(t.author),
          subtitle: Text(widget.authorUrl),
          onTap: () => _launchUrl(widget.authorUrl),
        ),

        ListTile(
          leading: const Icon(Icons.email),
          title: Text(t.email),
          subtitle: Text(widget.authorEmail),
          onTap: () => _launchEmail(widget.authorEmail),
        ),

        ListTile(
          leading: const Icon(Icons.bug_report),
          title: Text(t.reportBug),
          subtitle: Text(widget.reportBugUrl),
          onTap: () => _launchUrl(widget.reportBugUrl),
        ),

        ListTile(
          leading: const Icon(Icons.privacy_tip),
          title: Text(t.privacyPolicy),
          subtitle: Text(widget.privacyPolicyUrl),
          onTap: () => _launchUrl(widget.privacyPolicyUrl),
        ),

        UI.getBottomPaddingOfList(),
      ],
    );
  }
}
