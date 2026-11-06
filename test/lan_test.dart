import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:darkchess/services/guardian_service.dart';
import 'package:darkchess/services/lan_service.dart';

void main() {
  test('host and guest connect over loopback, exchange moves, and wrong PINs are refused', () async {
    final guestArrived = Completer<(LanLink, String)>();
    final problems = <String>[];
    final host = LanHost(
      pin: '4821',
      hostName: 'Host',
      hostColor: 0,
      tcIndex: 4,
      onGuest: (l, n) => guestArrived.complete((l, n)),
      onProblem: problems.add,
    );
    await host.start();

    // wrong PIN: refused with a readable message
    await expectLater(
      LanClient.connect(host: '127.0.0.1', pin: '0000', name: 'Eve'),
      throwsA(isA<LanException>().having((e) => e.message, 'message', contains('Wrong PIN'))),
    );

    // right PIN
    final (guestLink, welcome) = await LanClient.connect(host: '127.0.0.1', pin: '4821', name: 'Ann');
    expect(welcome['hostColor'], 0);
    expect(welcome['tc'], 4);
    final (hostLink, guestName) = await guestArrived.future.timeout(const Duration(seconds: 5));
    expect(guestName, 'Ann');

    // the guest moves before the host screen has attached: the message must not be lost
    guestLink.send({'t': 'move', 'u': 'e2e4', 'n': 1});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final got = Completer<Map<String, dynamic>>();
    hostLink.attach(got.complete);
    expect((await got.future.timeout(const Duration(seconds: 5)))['u'], 'e2e4');

    await guestLink.close();
    await hostLink.close();
    await host.stop();
  });

  test('every guardian event has a line in both voices', () {
    for (final e in GEvent.values) {
      expect(Guardian.say(e), isNotEmpty);
      expect(Guardian.say(e, trash: true), isNotEmpty);
    }
  });
}
