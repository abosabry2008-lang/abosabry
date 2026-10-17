// Smoke test for the ERP client.
//
// The application itself talks to a backend over HTTP and reads
// `shared_preferences`, so this test only asserts that the root widget can be
// constructed. Widget/integration tests against a live API belong in a
// dedicated harness.
import 'package:erp_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ErpApp can be constructed', () {
    expect(const ErpApp(), isNotNull);
  });
}
