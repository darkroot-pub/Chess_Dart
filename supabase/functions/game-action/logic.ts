// Pure chess helpers used by the edge function (kept separate so they can be unit-tested without a network).
import { Chess } from "npm:chess.js@1.0.0-beta.8";

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const UCI_RE = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

export const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

export function parseUci(uci: string): { from: string; to: string; promotion?: string } | null {
  if (typeof uci !== "string" || !UCI_RE.test(uci)) return null;
  return { from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci.length > 4 ? uci[4] : undefined };
}

/** Rebuilds the game from the stored UCI list so repetition and the fifty-move rule see the full history.
 *  Returns null when a stored move is illegal (corrupt data). */
export function replay(moves: string[]): Chess | null {
  const chess = new Chess();
  for (const u of moves) {
    const p = parseUci(u);
    if (!p) return null;
    try {
      if (!chess.move(p)) return null;
    } catch (_) {
      return null;
    }
  }
  return chess;
}

/** Game-over detection after `mover` just moved. Returns [result, reason] or null. */
export function outcomeAfter(chess: Chess, mover: "w" | "b"): [string, string] | null {
  if (chess.isCheckmate()) return [mover === "w" ? "1-0" : "0-1", "Checkmate"];
  if (chess.isStalemate()) return ["1/2-1/2", "Stalemate"];
  if (chess.isInsufficientMaterial()) return ["1/2-1/2", "Insufficient material"];
  if (chess.isThreefoldRepetition()) return ["1/2-1/2", "Threefold repetition"];
  if (chess.isDraw()) return ["1/2-1/2", "Fifty-move rule"];
  return null;
}

/** First four FEN fields (placement, turn, castling, en passant); counters are ignored on purpose. */
export const samePosition = (a: string, b: string) => a.split(" ").slice(0, 2).join(" ") === b.split(" ").slice(0, 2).join(" ");
