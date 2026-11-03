// Edge Function: authenticates the caller, validates every online action with a real rules engine (chess.js) and
// commits it through ONE atomic database function (public.server_apply_move / server_game_action), which locks the
// game row and re-checks membership, turn, position, clocks and game state. The client is never trusted for FEN,
// clocks, ratings, results or identity.
// Deploy:  supabase functions deploy game-action
import { createClient } from "npm:@supabase/supabase-js@2";

// ---- chess logic (inlined so the dashboard editor deploys a single file) ----
// Pure chess helpers used by the edge function (kept separate so they can be unit-tested without a network).
import { Chess } from "npm:chess.js@1.0.0-beta.8";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UCI_RE = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

function parseUci(uci: string): { from: string; to: string; promotion?: string } | null {
  if (typeof uci !== "string" || !UCI_RE.test(uci)) return null;
  return { from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci.length > 4 ? uci[4] : undefined };
}

/** Rebuilds the game from the stored UCI list so repetition and the fifty-move rule see the full history.
 *  Returns null when a stored move is illegal (corrupt data). */
function replay(moves: string[]): Chess | null {
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
function outcomeAfter(chess: Chess, mover: "w" | "b"): [string, string] | null {
  if (chess.isCheckmate()) return [mover === "w" ? "1-0" : "0-1", "Checkmate"];
  if (chess.isStalemate()) return ["1/2-1/2", "Stalemate"];
  if (chess.isInsufficientMaterial()) return ["1/2-1/2", "Insufficient material"];
  if (chess.isThreefoldRepetition()) return ["1/2-1/2", "Threefold repetition"];
  if (chess.isDraw()) return ["1/2-1/2", "Fifty-move rule"];
  return null;
}

/** First four FEN fields (placement, turn, castling, en passant); counters are ignored on purpose. */
const samePosition = (a: string, b: string) => a.split(" ").slice(0, 2).join(" ") === b.split(" ").slice(0, 2).join(" ");

// ---- handler ----

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ACTIONS = new Set(["move", "resign", "offer_draw", "accept_draw", "decline_draw", "timeout"]);

// Maps database exceptions (raised on purpose by the RPCs) to HTTP statuses. Anything else is a 500 with a generic text.
function dbError(message: string): Response {
  if (/not signed in/i.test(message)) return json({ error: "Not signed in" }, 401);
  if (/game not found/i.test(message)) return json({ error: "Game not found" }, 404);
  if (/not your game/i.test(message)) return json({ error: "Not your game" }, 403);
  if (/stale request|duplicate key/i.test(message)) return json({ error: "The position changed. Please try again." }, 409);
  if (/not your turn|not active|bad move|bad position|no draw offer|no one has run out|unknown action/i.test(message)) {
    return json({ error: message.replace(/^.*?:\s*/, "") }, 400);
  }
  console.error("game-action db error:", message);
  return json({ error: "Server error" }, 500);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: u } = await userClient.auth.getUser();
    const uid = u?.user?.id;
    if (!uid) return json({ error: "Not signed in" }, 401);

    let body: { game_id?: unknown; action?: unknown; uci?: unknown };
    try {
      body = await req.json();
    } catch (_) {
      return json({ error: "Bad request" }, 400);
    }
    const { game_id, action, uci } = body;
    if (typeof game_id !== "string" || !UUID_RE.test(game_id)) return json({ error: "Bad game id" }, 400);
    if (typeof action !== "string" || !ACTIONS.has(action)) return json({ error: "Unknown action" }, 400);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } }); // server-side only

    if (action !== "move") {
      const { data, error } = await admin.rpc("server_game_action", { p_game: game_id, p_player: uid, p_action: action });
      if (error) return dbError(error.message);
      return json({ game: data });
    }

    // ---- move: validate with chess.js against the position rebuilt from the stored moves, then commit atomically
    const parsed = typeof uci === "string" ? parseUci(uci) : null;
    if (!parsed) return json({ error: "Bad move" }, 400);

    const { data: g } = await admin.from("games").select("id,white_id,black_id,status,turn,fen,moves").eq("id", game_id).maybeSingle();
    if (!g) return json({ error: "Game not found" }, 404);
    if (uid !== g.white_id && uid !== g.black_id) return json({ error: "Not your game" }, 403);
    if (g.status !== "active") return json({ error: "Game is not active" }, 400);
    const myColor = uid === g.white_id ? "w" : "b";
    if (g.turn !== myColor) return json({ error: "Not your turn" }, 400);

    const chess = replay(g.moves as string[]);
    if (!chess || !samePosition(chess.fen(), g.fen)) {
      console.error("game-action: stored position does not match replay for game", game_id);
      return json({ error: "Game state is inconsistent" }, 409);
    }
    let mv;
    try {
      mv = chess.move(parsed);
    } catch (_) {
      mv = null;
    }
    if (!mv) return json({ error: "Illegal move" }, 400);

    const over = outcomeAfter(chess, myColor);
    const { data, error } = await admin.rpc("server_apply_move", {
      p_game: game_id, p_player: uid, p_uci: uci,
      p_expected_ply: (g.moves as string[]).length, p_expected_fen: g.fen,
      p_new_fen: chess.fen(), p_san: mv.san,
      p_over_result: over ? over[0] : null, p_over_reason: over ? over[1] : null,
    });
    if (error) return dbError(error.message);
    return json({ game: data });
  } catch (e) {
    console.error("game-action failure:", e instanceof Error ? e.message : "unknown");
    return json({ error: "Server error" }, 500);
  }
});
