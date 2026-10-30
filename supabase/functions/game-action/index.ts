// Edge Function: validates every online action server-side with a real rules engine (chess.js).
// Deploy:  supabase functions deploy game-action
import { createClient } from "npm:@supabase/supabase-js@2";
import { Chess } from "npm:chess.js@1.0.0-beta.8";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: u } = await userClient.auth.getUser();
    const uid = u?.user?.id;
    if (!uid) return json({ error: "Not signed in" }, 401);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!); // server-side only
    const { game_id, action, uci } = await req.json();
    const { data: g } = await admin.from("games").select("*").eq("id", game_id).single();
    if (!g) return json({ error: "Game not found" }, 404);
    if (uid !== g.white_id && uid !== g.black_id) return json({ error: "Not your game" }, 403);
    if (g.status !== "active") return json({ error: "Game is not active" }, 400);

    const myColor = uid === g.white_id ? "w" : "b";
    const now = Date.now();
    let whiteMs: number = g.white_ms, blackMs: number = g.black_ms;
    // clock only runs once white has moved
    if (g.moves.length > 0) {
      const el = now - new Date(g.last_move_at).getTime();
      if (g.turn === "w") whiteMs -= el; else blackMs -= el;
    }

    const finish = async (result: string, reason: string, patch: Record<string, unknown> = {}) => {
      const { data: upd } = await admin.from("games")
        .update({ ...patch, status: "finished", result, reason, white_ms: Math.max(0, whiteMs), black_ms: Math.max(0, blackMs), draw_offer_by: null })
        .eq("id", g.id).eq("status", "active").select().single();
      if (upd) await updateRatings(admin, g.white_id, g.black_id, result);
      return json({ game: upd ?? (await admin.from("games").select("*").eq("id", g.id).single()).data });
    };

    // timeout can be claimed by either player; the server decides
    if (action === "timeout") {
      if (g.moves.length > 0 && whiteMs <= 0) return await finish("0-1", "Timeout");
      if (g.moves.length > 0 && blackMs <= 0) return await finish("1-0", "Timeout");
      return json({ error: "No one has run out of time" }, 400);
    }
    if (action === "resign") return await finish(myColor === "w" ? "0-1" : "1-0", "Resignation");
    if (action === "offer_draw") {
      const { data } = await admin.from("games").update({ draw_offer_by: uid }).eq("id", g.id).select().single();
      return json({ game: data });
    }
    if (action === "decline_draw") {
      const { data } = await admin.from("games").update({ draw_offer_by: null }).eq("id", g.id).select().single();
      return json({ game: data });
    }
    if (action === "accept_draw") {
      if (!g.draw_offer_by || g.draw_offer_by === uid) return json({ error: "No draw offer to accept" }, 400);
      return await finish("1/2-1/2", "Draw by agreement");
    }

    if (action === "move") {
      if (g.turn !== myColor) return json({ error: "Not your turn" }, 400);
      if (g.moves.length > 0 && (myColor === "w" ? whiteMs : blackMs) <= 0) {
        return await finish(myColor === "w" ? "0-1" : "1-0", "Timeout");
      }
      if (typeof uci !== "string" || uci.length < 4) return json({ error: "Bad move" }, 400);
      const chess = new Chess(g.fen);
      let mv;
      try {
        mv = chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci.length > 4 ? uci[4] : undefined });
      } catch (_) { mv = null; }
      if (!mv) return json({ error: "Illegal move" }, 400);

      if (g.moves.length > 0) { // increment (not on white's first move)
        if (myColor === "w") whiteMs += g.inc_ms; else blackMs += g.inc_ms;
      }
      const newMoves = [...g.moves, uci];
      const patch = {
        fen: chess.fen(), turn: chess.turn(), moves: newMoves,
        white_ms: Math.max(0, whiteMs), black_ms: Math.max(0, blackMs),
        last_move_at: new Date(now).toISOString(), draw_offer_by: null,
      };
      await admin.from("game_moves").insert({ game_id: g.id, ply: newMoves.length, uci, san: mv.san, fen_after: chess.fen(), player_id: uid });

      let over: [string, string] | null = null;
      if (chess.isCheckmate()) over = [myColor === "w" ? "1-0" : "0-1", "Checkmate"];
      else if (chess.isStalemate()) over = ["1/2-1/2", "Stalemate"];
      else if (chess.isInsufficientMaterial()) over = ["1/2-1/2", "Insufficient material"];
      else if (chess.isThreefoldRepetition()) over = ["1/2-1/2", "Threefold repetition"];
      else if (chess.isDraw()) over = ["1/2-1/2", "Fifty-move rule"];
      if (over) return await finish(over[0], over[1], patch);

      const { data } = await admin.from("games").update(patch).eq("id", g.id).eq("turn", myColor).select().single();
      if (!data) return json({ error: "Move conflict, try again" }, 409);
      return json({ game: data });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

async function updateRatings(admin: any, whiteId: string, blackId: string, result: string) {
  const { data: ps } = await admin.from("profiles").select("*").in("id", [whiteId, blackId]);
  const w = ps.find((p: any) => p.id === whiteId), b = ps.find((p: any) => p.id === blackId);
  if (!w || !b) return;
  const sw = result === "1-0" ? 1 : result === "0-1" ? 0 : 0.5;
  const ew = 1 / (1 + Math.pow(10, (b.rating - w.rating) / 400));
  const K = 24;
  const nw = Math.max(100, Math.round(w.rating + K * (sw - ew)));
  const nb = Math.max(100, Math.round(b.rating + K * ((1 - sw) - (1 - ew))));
  await admin.from("profiles").update({
    rating: nw, games_played: w.games_played + 1, wins: w.wins + (sw === 1 ? 1 : 0),
    losses: w.losses + (sw === 0 ? 1 : 0), draws: w.draws + (sw === 0.5 ? 1 : 0),
  }).eq("id", whiteId);
  await admin.from("profiles").update({
    rating: nb, games_played: b.games_played + 1, wins: b.wins + (sw === 0 ? 1 : 0),
    losses: b.losses + (sw === 1 ? 1 : 0), draws: b.draws + (sw === 0.5 ? 1 : 0),
  }).eq("id", blackId);
}
