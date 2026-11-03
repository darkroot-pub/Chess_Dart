// Run with:  deno test --allow-net=registry.npmjs.org,deno.land --allow-read supabase/functions/game-action/logic_test.ts
// (Requires Deno. NOT executed in the authoring sandbox: Deno and npm were unavailable there.)
import { assert, assertEquals } from "jsr:@std/assert@1";
import { outcomeAfter, parseUci, replay } from "./logic.ts";

Deno.test("parseUci accepts valid and rejects malformed moves", () => {
  assertEquals(parseUci("e2e4"), { from: "e2", to: "e4", promotion: undefined });
  assertEquals(parseUci("e7e8q")?.promotion, "q");
  for (const bad of ["", "e2", "e2e9", "e2e4x", "E2E4", "e2e4; drop", "i2e4"]) assertEquals(parseUci(bad), null, bad);
});

Deno.test("replay rejects illegal stored moves", () => {
  assert(replay(["e2e4", "e7e5"]) !== null);
  assertEquals(replay(["e2e5"]), null);
});

Deno.test("fool's mate is checkmate for black", () => {
  const c = replay(["f2f3", "e7e5", "g2g4"])!;
  c.move({ from: "d8", to: "h4" });
  assertEquals(outcomeAfter(c, "b"), ["0-1", "Checkmate"]);
});

Deno.test("stalemate", () => {
  const c = replay([])!;
  c.load("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1");
  assertEquals(outcomeAfter(c, "w"), ["1/2-1/2", "Stalemate"]);
});

Deno.test("threefold repetition is detected because history is replayed", () => {
  const c = replay(["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"])!;
  assertEquals(outcomeAfter(c, "b"), ["1/2-1/2", "Threefold repetition"]);
});

Deno.test("castling and en passant are legal through replay", () => {
  assert(replay(["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1"]) !== null); // castling
  assert(replay(["e2e4", "a7a6", "e4e5", "d7d5", "e5d6"]) !== null); // en passant
});
