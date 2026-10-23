import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/services/network/danmaku_server.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse(url);
    final official = uri.origin == DanmakuServer.officialBase;
    if (official && (dandanCredentials['id']!.isEmpty || dandanCredentials['value']!.isEmpty)) {
      throw const DanmakuConfigurationException();
    }
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      if (official) ...{
        'X-Auth': 1,
        'X-AppId': dandanCredentials['id'],
        'X-Timestamp': timestamp,
        'X-Signature': generateDandanSignature(uri.path, timestamp),
      },
      ...headers,
    };

    try {
      final response = await (official ? DioFactory.apiDio : DioFactory.danmakuCustomDio).get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      if (!official) {
        // Do not leak the configured token URL via exception logging.
        throw Exception('自建弹幕服务请求失败（${e.response?.statusCode ?? e.type.name}）');
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}

class DanmakuConfigurationException implements Exception {
  const DanmakuConfigurationException();
  @override
  String toString() => '此安装包未配置弹弹play凭据，请在弹幕设置中填写自建弹幕服务器';
}
