import 'package:dio/dio.dart';

/// The browser already has its own HTTP client. Same Dio, no phone adapter.
Dio attachIo(Dio dio) => dio;
