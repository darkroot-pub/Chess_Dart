import 'dart:math';

/// Things the Guardian can react to.
enum GEvent { greet, userMove, userCapture, userCheck, aiCapture, aiCheck, losing, winning, win, lose, draw, undo, thinking, puzzleStart, puzzleOk, puzzleDone, puzzleWrong, hint, tip, tap,
  userBlunder, userQueenLost, aiQueenLost, castle, promote, slow, resign }

/// Kindred's lines. Short, in character, never repeats the same line twice in a row.
/// Two voices: the calm coach, and "taunt mode" (playful rage-bait, all in good fun: never about the person, only about the chess).
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
    GEvent.userBlunder: ['Careful, that piece was undefended.', 'Ouch. Check what the opponent can capture before each move.', 'That cost material. Slow down and scan the board.'],
    GEvent.userQueenLost: ['Your queen is gone. Stay calm and regroup.', 'A heavy loss. Look for counterplay.'],
    GEvent.aiQueenLost: ['You took their queen! Now keep it simple.', 'Their queen is off the board. Press on.'],
    GEvent.castle: ['Good, your king is safe.', 'Castling: king safe, rook active.'],
    GEvent.promote: ['A new queen! Use her well.', 'Promotion! Careful, stalemate tricks exist.'],
    GEvent.slow: ['Take your time. Careful thinking wins games.', 'Still thinking? Look for checks, captures and threats.'],
    GEvent.resign: ['Resigning is part of learning. Review it with me.', 'It is fine. Let\'s find what went wrong.'],
    GEvent.tap: [
      'Hehe, that tickles.',
      'Need a tip? Ask me anything.',
      'I\'m here. Let\'s play some chess.',
      'The flowers bloom when you play well.',
    ],
  };

  /// Taunt mode (settings: "Taunts"). Cheeky and competitive, never mean about the person.
  static const _trash = <GEvent, List<String>>{
    GEvent.greet: [
      'Oh, you showed up. Brave. Let\'s see how long that lasts.',
      'Another challenger? I have not even warmed up.',
      'Pick a side. It will not help.',
      'I have seen your rating. Bold of you to be here.',
    ],
    GEvent.userMove: [
      'That is your plan? Wow.',
      'Interesting. Wrong, but interesting.',
      'Take your time. You will need it.',
      'Is that a move or an accident?',
      'I have seen better moves from a screensaver.',
    ],
    GEvent.userCapture: [
      'Enjoy it. It is the only piece you will take.',
      'Cute. That was bait.',
      'You took it? Bold of you to think it was free.',
    ],
    GEvent.userCheck: [
      'Check? Aww, you found the button.',
      'Adorable. I will just step aside.',
      'Is that supposed to scare me?',
    ],
    GEvent.aiCapture: [
      'Thanks for the gift.',
      'Yum.',
      'Did you mean to leave that there?',
      'I will take that. You were not using it.',
    ],
    GEvent.aiCheck: [
      'Check. Run, little king.',
      'Your king looks nervous.',
      'Check. Want me to explain what that means?',
    ],
    GEvent.userBlunder: [
      'Wow. Did you really just hang that?',
      'That was a gift, right? Please say it was a gift.',
      'Blunder detected. Confidence: 100%.',
      'Free material! Thank you for your service.',
      'I did not even have to try.',
    ],
    GEvent.userQueenLost: [
      'You lost your QUEEN. Let that sink in.',
      'Rest in peace, queen. She deserved a better player.',
      'No queen, no hope. Just saying.',
    ],
    GEvent.aiQueenLost: [
      'Okay, okay. Lucky shot. Do not get used to it.',
      'That queen was just resting.',
      'Fine. Enjoy your five seconds of glory.',
    ],
    GEvent.castle: [
      'Hiding your king already?',
      'Castling? Running away early, I see.',
    ],
    GEvent.promote: [
      'A new queen. Do not get comfortable.',
      'Promoted? I was saving the mate anyway.',
    ],
    GEvent.slow: [
      'Did you fall asleep?',
      'Hello? Is anyone driving?',
      'The longer you think, the worse it looks.',
      'My patience is running out faster than your clock.',
    ],
    GEvent.resign: [
      'Running away already? I accept your surrender.',
      'Resigned? I barely got started.',
    ],
    GEvent.losing: [
      'You are losing and it shows.',
      'I would say resign, but I am enjoying this.',
      'Is this a speedrun to the loss screen?',
    ],
    GEvent.winning: [
      'Enjoy the lead. It is temporary.',
      'You are ahead? Suspicious. I am still not worried.',
    ],
    GEvent.win: [
      'Fine. You win. I demand a rematch.',
      'That was luck. Pure luck.',
      'I let you win. Obviously.',
    ],
    GEvent.lose: [
      'GG easy.',
      'Better luck next time. Maybe in a hundred games.',
      'Was that your best? Please say no.',
      'Try puzzles. Seriously.',
    ],
    GEvent.draw: [
      'A draw? Take it. You will never get closer.',
      'Draw. I was just being nice.',
    ],
    GEvent.undo: [
      'Taking it back? Coward.',
      'Undo will not fix the plan.',
      'You can delete the move, not the skill gap.',
    ],
    GEvent.thinking: ['Calculating how to ruin your day…', 'This will not take long.'],
    GEvent.hint: [
      'You need a hint already?',
      'Fine, here is a nudge. Try to keep up.',
    ],
    GEvent.tip: [
      'Tip: do not hang your queen. You are welcome.',
      'Tip: the pieces move differently. Look it up.',
      'Tip: think before you click. Revolutionary, I know.',
    ],
    GEvent.tap: [
      'Poking me will not save your king.',
      'Need a hint? Too bad.',
      'Stop touching me and play.',
      'Is that your best move? Tapping a character?',
    ],
  };

  /// [trash] picks the taunt voice when the event has taunt lines; otherwise the calm coach speaks.
  static String say(GEvent e, {bool trash = false}) {
    final l = (trash ? _trash[e] : null) ?? _lines[e] ?? const ['…'];
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
