import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';

void main() {
  test('critical status is reserved for the critical token', () {
    expect(MaatriTokens.statusColor('critical'), MaatriTokens.critical);
    expect(MaatriTokens.statusColor('warning'), MaatriTokens.warning);
    expect(MaatriTokens.statusColor('normal'), MaatriTokens.success);
  });

  test('regional font fallbacks include Indic-script families', () {
    expect(MaatriTokens.fontFallbacks, contains('Noto Sans Devanagari'));
    expect(MaatriTokens.fontFallbacks, contains('Noto Sans Malayalam'));
    expect(MaatriTokens.fontFallbacks, contains('Noto Sans Tamil'));
  });
}
