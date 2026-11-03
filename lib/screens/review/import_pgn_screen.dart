import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/pgn_import.dart';
import '../../widgets/cards/common.dart';
import 'review_screen.dart';

/// Paste any PGN (from chess.com, lichess, a book, a friend) and analyse it with Dark Chess AI.
class ImportPgnScreen extends StatefulWidget {
  const ImportPgnScreen({super.key});
  @override
  State<ImportPgnScreen> createState() => _ImportPgnScreenState();
}

class _ImportPgnScreenState extends State<ImportPgnScreen> {
  final _ctl = TextEditingController();
  String? _error;
  bool _save = true;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (d?.text == null || d!.text!.trim().isEmpty) {
      snack(context, 'The clipboard is empty');
      return;
    }
    setState(() {
      _ctl.text = d.text!;
      _error = null;
    });
  }

  void _analyse() {
    final r = PgnImport.parse(_ctl.text);
    if (r.record == null) {
      setState(() => _error = r.error);
      return;
    }
    setState(() => _error = null);
    final rec = r.record!;
    if (_save) context.read<AppState>().recordOnlineGame(rec); // stores once by id; same path as online games
    if (r.gamesFound > 1) snack(context, 'Several games found. Analysing the first one.');
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(record: rec)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analyse a PGN')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Paste a game in PGN format. Headers, comments and variations are fine; only the main line is analysed.', style: TextStyle(color: C.text2)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            minLines: 8,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
            decoration: InputDecoration(
              hintText: '[White "Me"]\n[Black "Friend"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 …',
              errorText: _error,
              errorMaxLines: 4,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('Paste'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => setState(() { _ctl.clear(); _error = null; }), icon: const Icon(Icons.clear), label: const Text('Clear'))),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _save,
            onChanged: (v) => setState(() => _save = v),
            title: const Text('Save to my games'),
            subtitle: const Text('Keeps it in your history and cloud so you can review it later. It does not change your rating or stats.'),
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _analyse,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Analyse game'),
          ),
        ]),
      ),
    );
  }
}
