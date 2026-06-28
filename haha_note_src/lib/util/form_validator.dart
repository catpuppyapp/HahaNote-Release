import 'package:characters/characters.dart';

import '../i18n/strings.g.dart';

abstract class FormValidator {

  static final _regexWindowsRootPath = RegExp(r'^[a-zA-Z]:[/\\]$');
  // 返回null则路径可能有效，否则返回错误信息
  static String? errIfPathNotAbsOrInvalid(final String? path, {required final bool isWindows, final bool allowRootPath = false}) {
    if(path == null || path.isEmpty) {
      return t.invalidPath + (", err code: 18302845");
    }

    if(!allowRootPath) {
      final rootPathErr = errIfIsRootPath(path);
      if(rootPathErr != null) {
        return rootPathErr;
      }
    }

    final String subStr;
    if(isWindows) {
      // at least "C:\" or "C:/" and another dir name(root path not allowed)
      if(path.length < 4) {
        return t.invalidPath + (", err code: 16109712");
      }

      final head = path.substring(0, 3);
      if(!(head.endsWith(":\\") || head.endsWith(":/"))) {
        return t.pathIsNotAbsolute + (", err code: 12253735");
      }

      subStr = path.substring(3);
    }else {
      // at least "/" and anther dir name(root path not allowed)
      if(path.length < 2) {
        return t.invalidPath + (", err code: 14790737");
      }

      if(!path.startsWith('/')) {
        return t.pathIsNotAbsolute + (", err code: 12041631");
      }

      subStr = path.substring(2);
    }

    // 后续字符串，必须包含非以下字符的字符，否则报错
    // :/\由于已经在上面验证过了，所以后面可有可无，但如果没有非:/\的字符，则肯定是无效路径，
    // 例如：C:/// 就是无效路径
    // 如果后面只有空字符，理论上有的系统允许空字符串做文件名，但我不允许
    // 其他的就是一些无效的字符，统统添加进去
    final List<String> invalidCharsForRestPath = [":", "/", "\\", " ", '"', "'"];

    for(final s in subStr.characters) {
      // 如果找到一个非无效字符的字符，则有效。
      if(!invalidCharsForRestPath.contains(s)) {
        return null;
      }
    }

    // 可能是绝对路径或者是"C://///" 之类的无效路径，又或者 "/       "root路径后面只有空字符
    // 后面的(2)是给开发者看的，用来和上面返回的无效路径区分
    return "${t.invalidPath} (err code: 16115578)";
  }

  // static String? checkMail(String? value) {
  //   final emptyCheckResult = checkEmpty(value);
  //   if (emptyCheckResult != null) {
  //     return emptyCheckResult;
  //   }
  //
  //   if (!value!.contains('@')) return t.invalidEmail;
  //   return null;
  // }

  static String? errIfPathEmpty(String? value) {
    return errIfNullOrEmpty(value);
  }

  static String? errIfNullOrEmpty(String? value) {
    if (value == null || value.isEmpty) return t.pleaseInput;

    return null;
  }


  static final _regexUsername = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_\-]{4,20}$');
  static String? errorIfUsernameInvalid(String? value) {
    final emptyErr = errIfPathEmpty(value);
    if(emptyErr != null) {
      return emptyErr;
    }
    
    if(!_regexUsername.hasMatch(value!)) {
      return t.usernameInvalid(pattern: "a-zA-Z0-9, _-", minLength: "5");
    }

    return null;
  }


  static final _regexPassword = RegExp(r'^[a-zA-Z0-9~!#$^&*()\-+_={}\[\]]{8,72}$');
  static String? errorIfPasswordInvalid(String? value) {
    final emptyErr = errIfPathEmpty(value);
    if(emptyErr != null) {
      return emptyErr;
    }

    if(!_regexPassword.hasMatch(value!)) {
      return t.passwordInvalid(pattern: "a-zA-Z0-9, _-~!#", minLength: "8");
    }

    return null;
  }


  static final _regexEmail = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,80}$');
  static String? errorIfEmailInvalid(String? value) {
    final emptyErr = errIfPathEmpty(value);
    if(emptyErr != null) {
      return emptyErr;
    }

    if(!_regexEmail.hasMatch(value!)) {
      return t.emailInvalid;
    }

    return null;
  }

  static String? errIfIsRootPath(String? path) {
    if(path == null || path == "") {
      return t.invalidPath+ (", err code: 17397100");
    }

    // unix root len = 1, windows root len = 3 (例如：C:/ 或 C:\)
    if(path.length > 3) {
      return null;
    }

    if(path == '/') {
      return t.rootPathIsNotAllowed+ (", err code: 19962089");
    }

    if(_regexWindowsRootPath.hasMatch(path)) {
      return t.rootPathIsNotAllowed + (", err code: 18524994");
    }

    return null;
  }

  static final _regexRedeemCode = RegExp(r'^[a-zA-Z0-9]{32,64}$');
  static String? errIfRedeemCodeInvalid(String? value) {
    final emptyErr = errIfNullOrEmpty(value);
    if(emptyErr != null) {
      return emptyErr;
    }

    if(!_regexRedeemCode.hasMatch(value!)) {
      return t.redeemCodeInvalid;
    }

    return null;
  }

}
