import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rishfy/core/errors/app_exception.dart';
import 'package:rishfy/features/auth/data/datasources/auth_remote_datasource.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio mockDio;
  late AuthRemoteDataSource dataSource;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockDio = _MockDio();
    dataSource = AuthRemoteDataSource(mockDio);
  });

  group('AuthRemoteDataSource.login', () {
    test('rethrows mapped AppExceptions from Dio', () async {
      final RequestOptions options = RequestOptions(path: '/api/v1/auth/login');
      const UnauthorizedException appError =
          UnauthorizedException(message: 'Invalid credentials');

      when(
        () => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
          error: appError,
        ),
      );

      await expectLater(
        dataSource.login(
          identifier: '+255700000001',
          password: 'Password123',
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (UnauthorizedException error) => error.message,
            'message',
            'Invalid credentials',
          ),
        ),
      );
    });

    test('wraps unexpected response payloads as contract mismatches', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/v1/auth/login'),
          statusCode: 200,
          data: <String, dynamic>{'success': true},
        ),
      );

      await expectLater(
        dataSource.login(
          identifier: '+255700000001',
          password: 'Password123',
        ),
        throwsA(
          isA<ServerException>()
              .having(
                (ServerException error) => error.code,
                'code',
                'AUTH_CONTRACT_MISMATCH',
              )
              .having(
                (ServerException error) => error.message,
                'message',
                'Authentication service returned an unexpected response.',
              ),
        ),
      );
    });
  });
}
