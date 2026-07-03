// Semantic colorizer for Elixir/Erlang term strings (redbug payloads, console
// results). Pure + line-local: tokenizes ONE line into role-tagged segments so
// the caller can render each with a theme hue. No cross-line state, so callers
// wrap first, then colorize each line independently.

export type TermRole = "atom" | "str" | "num" | "ref" | "key" | "plain"

export type TermSeg = { t: string; role: TermRole }

// Ordered matchers; first hit at the cursor wins. Anything unmatched is consumed
// one char at a time into a coalesced "plain" run (brackets, commas, =>, |, ws).
const RULES: [TermRole, RegExp][] = [
  // double-quoted string / single-quoted charlist (with escapes)
  ["str", /^"(?:[^"\\]|\\.)*"/],
  ["str", /^'(?:[^'\\]|\\.)*'/],
  // #PID<..> #Reference<..> #Port<..> #Function<..>, and bare <0.42.0>
  ["ref", /^#(?:PID|Reference|Port|Function|[A-Za-z]+)?<[^>]*>/],
  ["ref", /^<\d+\.\d+\.\d+>/],
  // keyword-list / map key: `name:` followed by whitespace (not `::`)
  ["key", /^[a-z_][A-Za-z0-9_]*:(?=\s)/],
  // quoted atom :"foo bar"
  ["atom", /^:"(?:[^"\\]|\\.)*"/],
  // atom :foo, :foo@bar, :ok?, module alias Foo.Bar, and true/false/nil
  ["atom", /^:[A-Za-z_][A-Za-z0-9_@]*[?!]?/],
  ["atom", /^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*/],
  ["atom", /^(?:true|false|nil)\b/],
  // number: ints (underscored), floats, sci, negative
  ["num", /^-?\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?/]
]

export function colorizeTerm(line: string): TermSeg[] {
  const out: TermSeg[] = []
  let i = 0
  let plain = ""
  const flush = () => {
    if (plain !== "") {
      out.push({ t: plain, role: "plain" })
      plain = ""
    }
  }

  while (i < line.length) {
    const rest = line.slice(i)
    let matched = false
    for (const [role, re] of RULES) {
      const m = re.exec(rest)
      if (m && m[0].length > 0) {
        flush()
        const last = out[out.length - 1]
        if (last && last.role === role) last.t += m[0]
        else out.push({ t: m[0], role })
        i += m[0].length
        matched = true
        break
      }
    }
    if (!matched) {
      plain += line[i]
      i += 1
    }
  }
  flush()
  return out
}

// ponytail: assert-based self-check; run `bun src/term.ts` to verify the parser.
function demo() {
  const assert = (c: boolean, m: string) => {
    if (!c) throw new Error("term self-check failed: " + m)
  }
  const roles = (s: string) => colorizeTerm(s).map((x) => x.role)
  const text = (s: string) => colorizeTerm(s).map((x) => x.t).join("")

  // round-trip: segments always reconstruct the input
  for (const s of ['%{status: :ok, n: 42}', '[1, 5]', '<0.42.0>: {tick, 42}', '"hi\\"x"']) {
    assert(text(s) === s, `roundtrip ${s}`)
  }
  assert(roles(":ok").join() === "atom", ":ok is atom")
  assert(colorizeTerm('%{status: :ok}').some((s) => s.role === "key" && s.t === "status:"), "map key")
  assert(colorizeTerm("[1, 5]").some((s) => s.role === "num" && s.t === "1"), "number")
  assert(colorizeTerm('"hello"').some((s) => s.role === "str"), "string")
  assert(colorizeTerm("<0.42.0>").some((s) => s.role === "ref"), "pid ref")
  assert(colorizeTerm("MyApp.Repo").some((s) => s.role === "atom" && s.t === "MyApp.Repo"), "alias")
  // eslint-disable-next-line no-console
  console.log("term.ts self-check ok")
}

if (import.meta.main) demo()
