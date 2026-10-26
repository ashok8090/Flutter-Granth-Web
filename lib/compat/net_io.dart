import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Keep-alive pool used on the phone. Not compiled for the website.
Dio attachIo(Dio dio) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()
      ..maxConnectionsPerHost = 8
      ..idleTimeout = const Duration(seconds: 30),
  );
  return dio;
}
