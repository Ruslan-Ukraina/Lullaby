// webpatch-syntax: the tool list of the Compatibility page, as the webpatch leaves it
// (the two tool-list gates in steam/hook/feats/webpatch.c). Steam's own component is cut out of the
// patched chunk and run with stand-ins for what it imports:
//   a Windows game, where Lullaby is the default: the list holds Lullaby and nothing else, with Lullaby chosen;
//   a game with a macOS build, no default: "Native" (in Steam's language) and Lullaby, "Native" chosen;
//   no tools at all: no list.
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");

if (src.indexOf("window.LBLN") < 0) process.exit(0); // a chunk without the compat page

// From the helper that names a tool (it reads `.aliases.find(`) to the end of the list component.
const helperAt = src.search(/function \w+\((\w+),(\w+)\)\{if\(!\1\|\|!\2\)return null;const \w+=\2\.aliases\.find\(/);
const compMatch = /function (\w+)\((\w+)\)\{const\{label:\w+,nAppId:\w+\}=\2,/.exec(src);
if (helperAt < 0 || !compMatch) { console.error("lbtoollist-check: Steam's tool list component was not found"); process.exit(1); }
let depth = 0, end = -1;
for (let k = src.indexOf("{", compMatch.index); k < src.length; k++) {
  if (src[k] === "{") depth++;
  else if (src[k] === "}" && --depth === 0) { end = k + 1; break; }
}
const code = src.slice(Math.min(helperAt, compMatch.index), end) + ";return " + compMatch[1];

let failed = 0;
function check(ok, what) { if (!ok) { console.error("lbtoollist-check: " + what); failed++; } }

function run(data, language) {
  global.window = { LBLN: language };
  global.SteamClient = { Settings: { GetCurrentLanguage: () => Promise.resolve(language) } };
  const mock = (key) => new Proxy(function () { return { EnableSteamPlayForOthersDropdownButton: "x" }; }, {
    get(_, prop) {
      if (typeof prop === "symbol") return undefined;
      switch (prop) {
        case "jsx": case "jsxs": return (c, props) => ({ c, props });
        case "we": return (tok, x) => (x ? tok + "(" + x + ")" : tok);
        case "uH": return (a) => a;
        case "VI": return () => [false];
        case "cT": return () => [{ isLoading: false, data }, () => {}];
        case "OK": return "OK";
        default: return key + "." + String(prop);
      }
    }
  });
  const scope = new Proxy({}, { has: (_, k) => typeof k === "string" && !(k in globalThis), get: (_, k) => (typeof k === "symbol" ? undefined : mock(k)) });
  const component = new Function("scope", "with(scope){" + code + "}")(scope);
  const out = component({ label: "label", nAppId: 7 });
  return out && out.props;
}

const lullaby = { name: "lullaby", display_name: "Dormison (Lullaby)", is_active: true, is_legacy: false, is_incompatible: false };

let props = run({ tools: [lullaby], aliases: [], default_tool_identifier: "lullaby", selected_tool_identifier: "" }, "ukrainian");
check(props && props.rgOptions.length === 1 && props.rgOptions[0].data === "lullaby", "a Windows game's list is Lullaby alone");
check(props && props.selectedOption === "lullaby", "Lullaby is the choice where it is the default and nothing is chosen");

props = run({ tools: [lullaby], aliases: [], default_tool_identifier: "lullaby", selected_tool_identifier: "lullaby" }, "english");
check(props && props.selectedOption === "lullaby", "Lullaby chosen stays chosen");

const native = { uk: "Нативний", ru: "Нативный" };
for (const [language, label] of [["ukrainian", native.uk], ["russian", native.ru], ["english", "Native"], ["", "Native"], ["klingon", "Native"]]) {
  props = run({ tools: [lullaby], aliases: [], default_tool_identifier: "", selected_tool_identifier: "" }, language);
  const first = props && props.rgOptions[0];
  check(first && first.data === "" && first.label === label, "a game with a macOS build starts its list with '" + label + "' (" + language + ")");
  check(props && props.rgOptions.length === 2 && props.rgOptions[1].data === "lullaby", "and offers Lullaby after it (" + language + ")");
  check(props && props.selectedOption === "", "and has Native chosen (" + language + ")");
}

check(!run({ tools: [], aliases: [], default_tool_identifier: "", selected_tool_identifier: "" }, "english"), "no tools, no list");

if (failed) process.exit(1);
