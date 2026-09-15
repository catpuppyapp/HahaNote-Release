import 'package:dio/dio.dart';
import 'package:webdav_client/src/auth.dart';

/// store auth type and value read from http header 'www-authenticate'
class AuthTypeValue {
  final AuthType type;
  final String value;

  const AuthTypeValue._({required this.type, required this.value});


  static AuthTypeValue createBasic(final String value) {
    return AuthTypeValue._(type: AuthType.BasicAuth, value: value);
  }

  static AuthTypeValue createDigest(final String value) {
    return AuthTypeValue._(type: AuthType.DigestAuth, value: value);
  }

  bool isBasic() => type == AuthType.BasicAuth;
  bool isDigest() => type == AuthType.DigestAuth;

  static AuthTypeValue? parseFromHeaders(Headers headers) {
    // List<String>?
    final values = headers['www-authenticate'];
    if(values == null || values.isEmpty) {
      return null;
    }

    AuthTypeValue? fallback;
    for(final v in values) {
      final trimmedLowerCase = v.trim().toLowerCase();
      if(trimmedLowerCase.startsWith('basic ')) {
        // first choice
        return AuthTypeValue.createBasic(v);
      }else if(trimmedLowerCase.startsWith('digest ')) {
        // do not return at here, since maybe basic after the fallback
        fallback = AuthTypeValue.createDigest(v);
      }
    }

    return fallback;
  }

  @override
  String toString() {
    return 'type: $type, value: $value';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthTypeValue &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          value == other.value;

  @override
  int get hashCode => Object.hash(type, value);
}
