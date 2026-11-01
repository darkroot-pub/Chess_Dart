import 'dart:math';

/// Things the Guardian can react to.
enum GEvent { greet, userMove, userCapture, userCheck, aiCapture, aiCheck, losing, winning, win, lose, draw, undo, thinking, puzzleStart, puzzleOk, puzzleDone, puzzleWrong, hint, tip, tap }

/// Kindred's lines. Short, in character, never repeats the same line twice in a row.
class Guardian {
  static const name = 'Kindred';
  static final _r = Random();
  static final _last = <GEvent, String>{};

  static const _lines = <GEvent, List<String>>{
    GEvent.greet: [
      'The board is set. Show me what you can do.',
      'Let\'s begin. I\'ll be watching every move.',
      'Ready when you are. Breathe, then play.',
      'A new game, a new story. Make it a good one.',
    ],
    GEvent.userMove: [
      'Nice. Keep your pieces working together.',
      'Hmm, interesting choice.',
      'Calm and steady. I like it.',
      'Good development. Don\'t forget your king.',
      'Think about what your opponent wants next.',
    ],
    GEvent.userCapture: [
      'Clean capture!',
      'Well taken. Just check it was safe.',
      'One less piece to worry about.',
      'That\'s the way!',
    ],
    GEvent.userCheck: [
      'Check! Press the attack.',
      'The king feels the pressure.',
      'Check. Keep the initiative.',
    ],
    GEvent.aiCapture: [
      'Careful, they took a piece.',
      'Ouch. Let\'s win it back.',
      'Don\'t panic. Look for a recapture.',
    ],
    GEvent.aiCheck: [
      'Check! Protect your king.',
      'Stay calm. Block, capture or run.',
      'Your king is in danger. Look at every escape.',
    ],
    GEvent.losing: [
      'We\'re behind, but games turn quickly.',
      'Slow down and look for tactics.',
    ],
    GEvent.winning: [
      'You\'re ahead. Trade pieces and stay safe.',
      'Good position. Don\'t rush, just be precise.',
    ],
    GEvent.win: [
      'Victory! I knew you could do it.',
      'Beautifully played. I\'m proud of you.',
      'Checkmate. That was a great game.',
    ],
    GEvent.lose: [
      'Every loss teaches something. Review it with me.',
      'Not this time. We\'ll come back stronger.',
      'It happens to everyone. Open the review and find the turning point.',
    ],
    GEvent.draw: [
      'A draw. Hard to hold, hard to break.',
      'Honours even. Next time, we push harder.',
    ],
    GEvent.undo: ['Taking it back? Think before the next one.', 'A second chance. Use it well.'],
    GEvent.thinking: ['The engine is thinking…', 'Let\'s see what they try.'],
    GEvent.puzzleStart: ['Look for checks, captures and threats first.', 'Take your time. There is one best move.', 'Is any piece undefended?'],
    GEvent.puzzleOk: ['Yes! Keep going.', 'Right move. What\'s next?', 'You see it.'],
    GEvent.puzzleDone: ['Solved! Sharp eyes.', 'Perfect. That one was tricky.', 'Another one for the collection!'],
    GEvent.puzzleWrong: ['Not quite. Look again.', 'Close, but there\'s something stronger.', 'Try a forcing move.'],
    GEvent.hint: ['Look at where the arrow starts.', 'Here\'s a nudge. Now work out why it\'s good.'],
    GEvent.tip: [
      'Control the centre early.',
      'Develop knights before bishops, and castle early.',
      'Don\'t move the same piece twice in the opening without reason.',
      'Before every move ask: what does it threaten, and what does it leave unprotected?',
      'In the endgame, activate your king.',
      'Rooks belong on open files.',
      'A knight on the rim is dim.',
      'When ahead in material, trade pieces, not pawns.',
    ],
    GEvent.tap: [
      'Hehe, that tickles.',
      'Need a tip? Ask me anything.',
      'I\'m here. Let\'s play some chess.',
      'The flowers bloom when you play well.',
    ],
  };

  static String say(GEvent e) {
    final l = _lines[e] ?? const ['…'];
    var s = l[_r.nextInt(l.length)];
    if (l.length > 1) {
      var guard = 0;
      while (s == _last[e] && guard++ < 6) {
        s = l[_r.nextInt(l.length)];
      }
    }
    _last[e] = s;
    return s;
  }
}
