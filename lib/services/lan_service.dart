import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Problems the player can fix (wrong address, wrong PIN...). The message is meant to be shown as is.
class LanException implements Exception {
  final String message;
  const LanException(this.message);
  @override
  String toString() => message;
}

/// One direct phone-to-phone connection (TCP, newline-separated JSON). Works over a phone hotspot or any shared
/// Wi-Fi, no internet needed. Messages that arrive before a listener is attached are kept, so none are lost while
/// the game screen is still opening.
class LanLink {
  static const _maxLine = 4096; // a chess message is tiny; anything bigger is not ours
  final Socket _socket;
  final List<int> _buf = [];
  final List<Map<String, dynamic>> _pending = [];
  void Function(Map<String, dynamic>)? _handler;
  void Function()? _onClose;
  StreamSubscription<List<int>>? _sub;
  Timer? _beat;
  DateTime _lastRx = DateTime.now();
  bool closed = false;

  LanLink(this._socket) {
    try {
      _socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _sub = _socket.listen(_onData, onDone: _shutdown, onError: (_) => _shutdown(), cancelOnError: true);
    unawaited(_socket.done.then((_) {}, onError: (_) => _shutdown()));
    // keep-alive: a silent connection for 15 s counts as lost (phone left the hotspot, app killed...)
    _beat = Timer.periodic(const Duration(seconds: 4), (_) {
      if (DateTime.now().difference(_lastRx) > const Duration(seconds: 15)) {
        _shutdown();
      } else {
        send({'t': 'ping'});
      }
    });
  }

  String get remoteAddress {
    try {
      return _socket.remoteAddress.address;
    } catch (_) {
      return '';
    }
  }

  /// Starts delivering messages to [handler] (in arrival order, including ones that came earlier).
  void attach(void Function(Map<String, dynamic>) handler, {void Function()? onClose}) {
    _handler = handler;
    _onClose = onClose;
    final early = List<Map<String, dynamic>>.of(_pending);
    _pending.clear();
    for (final m in early) {
      handler(m);
    }
    if (closed) Future.microtask(() => _onClose?.call());
  }

  /// Keeps incoming messages for the next [attach] instead of delivering them (used between handshake and game).
  void pauseDelivery() {
    _handler = null;
    _onClose = null;
  }

  void send(Map<String, dynamic> m) {
    if (closed) return;
    try {
      _socket.add(utf8.encode('${jsonEncode(m)}\n'));
    } catch (_) {
      _shutdown();
    }
  }

  void _onData(List<int> chunk) {
    _lastRx = DateTime.now();
    for (final b in chunk) {
      if (b == 10) {
        _line();
      } else {
        _buf.add(b);
        if (_buf.length > _maxLine) {
          _shutdown();
          return;
        }
      }
    }
  }

  void _line() {
    if (_buf.isEmpty) return;
    final bytes = List<int>.of(_buf);
    _buf.clear();
    Map<String, dynamic>? m;
    try {
      final d = jsonDecode(utf8.decode(bytes));
      if (d is Map) m = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (m == null || m['t'] == 'ping') return; // garbage and keep-alives are ignored
    final h = _handler;
    if (h == null) {
      if (_pending.length < 200) _pending.add(m);
    } else {
      h(m);
    }
  }

  void _shutdown() {
    if (closed) return;
    closed = true;
    _beat?.cancel();
    _sub?.cancel();
    try {
      _socket.destroy();
    } catch (_) {}
    _onClose?.call();
  }

  /// Orderly close: pending data (for example the last "end" message) is flushed first. Does not call onClose.
  Future<void> close() async {
    if (closed) return;
    closed = true;
    _beat?.cancel();
    try {
      await _socket.flush().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await _sub?.cancel();
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

/// The phone that creates the game. Listens on [port]; the friend connects with this phone's address and the PIN.
class LanHost {
  static const port = 47631;
  final String pin;
  final String hostName;
  final int hostColor; // 0 white, 1 black
  final int tcIndex;
  final void Function(LanLink link, String guestName) onGuest;
  final void Function(String message) onProblem;
  ServerSocket? _server;
  int _wrongPins = 0;
  bool _taken = false;

  LanHost({required this.pin, required this.hostName, required this.hostColor, required this.tcIndex, required this.onGuest, required this.onProblem});

  static String newPin() => (1000 + Random.secure().nextInt(9000)).toString();

  Future<void> start() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
    } on SocketException {
      throw const LanException('Could not open the game port. Close other DarkChess games and try again.');
    }
    _server!.listen(_accept, onError: (_) {});
  }

  void _accept(Socket s) {
    if (_taken) {
      s.destroy(); // one opponent per game
      return;
    }
    final link = LanLink(s);
    var answered = false;
    final timeout = Timer(const Duration(seconds: 8), () {
      if (!answered) link.close();
    });
    link.attach((m) {
      if (answered) return;
      answered = true;
      timeout.cancel();
      if (m['t'] != 'hello' || m['v'] != 1) {
        link.send({'t': 'reject', 'why': 'version'});
        link.close();
        return;
      }
      if (m['pin'] != pin) {
        _wrongPins++;
        link.send({'t': 'reject', 'why': 'pin'});
        link.close();
        if (_wrongPins >= 5) {
          stop();
          onProblem('Too many wrong PIN attempts. Create a new game to get a new PIN.');
        }
        return;
      }
      var name = (m['name'] is String ? m['name'] as String : '').trim();
      if (name.isEmpty) name = 'Guest';
      if (name.length > 20) name = name.substring(0, 20);
      _taken = true;
      link.send({'t': 'welcome', 'name': hostName, 'hostColor': hostColor, 'tc': tcIndex});
      link.pauseDelivery(); // the guest may move right away; keep it for the game screen
      stop();
      onGuest(link, name);
    }, onClose: () {
      timeout.cancel();
    });
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    try {
      await s?.close();
    } catch (_) {}
  }
}

/// The phone that joins a game created on another phone.
class LanClient {
  static Future<(LanLink, Map<String, dynamic>)> connect({required String host, required String pin, required String name, int port = LanHost.port}) async {
    final addr = InternetAddress.tryParse(host.trim());
    if (addr == null || addr.type != InternetAddressType.IPv4) {
      throw const LanException('Type the address as four numbers, for example 192.168.43.1');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) throw const LanException('The PIN has 4 digits.');
    Socket s;
    try {
      s = await Socket.connect(addr, port, timeout: const Duration(seconds: 6));
    } catch (_) {
      throw const LanException('Could not reach that phone. Check that both phones are on the same hotspot or Wi-Fi, the address is right and the other phone is waiting on its host screen.');
    }
    final link = LanLink(s);
    final reply = Completer<Map<String, dynamic>>();
    link.attach((m) {
      if (!reply.isCompleted) reply.complete(m);
    }, onClose: () {
      if (!reply.isCompleted) reply.completeError(const LanException('The other phone closed the connection.'));
    });
    link.send({'t': 'hello', 'v': 1, 'pin': pin, 'name': name});
    Map<String, dynamic> m;
    try {
      m = await reply.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      await link.close();
      throw const LanException('The other phone did not answer.');
    }
    if (m['t'] == 'reject') {
      await link.close();
      throw LanException(m['why'] == 'pin' ? 'Wrong PIN. Check the 4 digits on the other phone.' : 'The two apps are different versions. Update both.');
    }
    final hc = m['hostColor'], tc = m['tc'];
    if (m['t'] != 'welcome' || (hc != 0 && hc != 1) || tc is! int || tc < 0) {
      await link.close();
      throw const LanException('Unexpected answer from the other phone.');
    }
    link.pauseDelivery();
    return (link, m);
  }
}

/// This phone's addresses on the local network, best candidates first (hotspot addresses are listed first).
Future<List<(String, String)>> lanAddresses() async {
  final out = <(String, String)>[];
  try {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) out.add((i.name, a.address));
      }
    }
  } catch (_) {}
  int rank((String, String) e) {
    final ip = e.$2;
    if (ip.startsWith('192.168.43.') || ip.startsWith('172.20.10.') || ip.startsWith('192.168.49.')) return 0; // common hotspot ranges
    if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) return 1;
    return 2;
  }

  out.sort((a, b) => rank(a).compareTo(rank(b)));
  return out;
}
