import 'package:flutter_test/flutter_test.dart';
import 'package:revv_app/core/app_links.dart';

void main() {
  test('privacy policy url accepts public http links', () {
    expect(
      AppLinks.uriFrom('https://www.notion.so/revv-privacy-policy')?.host,
      'www.notion.so',
    );
  });

  test('privacy policy url rejects empty or non-web values', () {
    expect(AppLinks.uriFrom(''), isNull);
    expect(AppLinks.uriFrom('not-a-url'), isNull);
    expect(AppLinks.uriFrom('mailto:privacy@example.com'), isNull);
  });
}
