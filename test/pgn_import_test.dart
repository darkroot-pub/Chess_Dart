import 'package:flutter_test/flutter_test.dart';
import 'package:darkchess/services/chess_service/pgn_import.dart';

void main() {
  test('reads headers, comments, variations and NAGs', () {
    const pgn = '[White "Ann"]\n[Black "Bob"]\n[Result "1-0"]\n[Date "2024.05.06"]\n\n'
        '1. e4 {best by test} e5 (1... c5 2. Nf3) 2. Nf3 \$1 Nc6 3. Bb5 a6 1-0';
    final r = PgnImport.parse(pgn);
    expect(r.error, isNull);
    expect(r.record!.ucis, ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6']);
    expect(r.record!.white, 'Ann');
    expect(r.record!.result, '1-0');
    expect(r.record!.date.startsWith('2024-05-06'), isTrue);
  });

  test('rejects an illegal move and names it', () {
    final r = PgnImport.parse('1. e4 e5 2. Ke3');
    expect(r.record, isNull);
    expect(r.error, contains('Ke3'));
  });

  test('empty and move-less input is refused', () {
    expect(PgnImport.parse('   ').record, isNull);
    expect(PgnImport.parse('[White "x"]\n\n*').record, isNull);
  });

  test('castling written with zeros', () {
    final r = PgnImport.parse('1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 *');
    expect(r.error, isNull);
    expect(r.record!.ucis[6], 'e1g1');
  });
}
