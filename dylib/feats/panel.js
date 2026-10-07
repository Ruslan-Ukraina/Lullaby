// NotProton's settings in Steam (docs/ROADMAP.md section 5): the block under Properties >
// Compatibility (a game's own values) and under Settings > Compatibility (values for all
// games), each with its quick rows and an Advanced dialog, drawn with Steam's own controls.
//
// The webpatch puts this function expression into the page twice and calls it with the
// names the page's module gives React's JSX runtime (J), Steam's dialog controls (B),
// React (R) and React DOM (D, may be null). Everything the panel shows comes from the catalog notproton-settings answers
// with (NotProtonSettings): it names no setting, key or text of its own, except the three
// lines below for when the catalog cannot be reached. Requests travel as virtual files
// under steamloopback.host (dylib/feats/settingsbridge.c); the dylib puts its token in.
//
// Kept to ASCII: dylib/embed_js.py embeds it as a C string.
(function (J, B, R, D) {
  "use strict";
  var TOKEN = "__NP_SETTINGS_TOKEN__";
  var FALLBACK = {
    en: "NotProton settings are unavailable: %@",
    uk: "\u041d\u0430\u043b\u0430\u0448\u0442\u0443\u0432\u0430\u043d\u043d\u044f NotProton \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u0456: %@",
    ru: "\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 NotProton \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u044b: %@"
  };
  var DOT = " \u00b7 ";
  // Steam's controls the panel draws with. Their names are the page's own and not part of
  // the webpatch anchors, so a Steam update can rename one; the panel then says so rather
  // than take the Properties page down with it.
  var MISSING = ["y4", "Vb", "FO", "$n", "m", "D0"].filter(function (k) {
    var t = B && B[k] ? typeof B[k] : "";
    return t !== "function" && t !== "object" && t !== "string";
  });
  if (!R || typeof R.useState !== "function" || typeof R.useEffect !== "function") MISSING.push("React");

  // React elements without JSX: el(type, props, ...children).
  function el(type, props) {
    var kids = [];
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c !== null && c !== undefined && c !== false) kids.push(c);
    }
    var p = {}, key;
    for (var k in props || {}) {
      if (k === "key") key = props[k];
      else p[k] = props[k];
    }
    if (kids.length === 1) p.children = kids[0];
    else if (kids.length > 1) p.children = kids;
    return kids.length > 1 ? J.jsxs(type, p, key) : J.jsx(type, p, key);
  }

  // ---- requests -------------------------------------------------------------------

  function b64url(text) {
    var bytes = new TextEncoder().encode(text), bin = "";
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  var seq = 0;
  function requestPath(request) {
    seq += 1;
    return "/notproton-settings/" + TOKEN + "/" + Date.now().toString(36) + seq.toString(36) + "/" +
      b64url(JSON.stringify(request)) + ".json";
  }
  function ask(request) {
    return fetch("https://steamloopback.host" + requestPath(request), { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .catch(function (e) { return { ok: false, error: String(e && e.message || e) }; });
  }
  var catalogPromise = null;
  function loadCatalog() {
    if (!catalogPromise) {
      catalogPromise = ask({ op: "catalog" }).then(function (a) {
        if (!a.ok) catalogPromise = null;
        return a;
      });
    }
    return catalogPromise;
  }
  function language() {
    try {
      return Promise.resolve(SteamClient.Settings.GetCurrentLanguage()).then(langOf, function () { return "en"; });
    } catch (e) {
      return Promise.resolve("en");
    }
  }
  function langOf(name) {
    var n = String(name || "").toLowerCase();
    return n === "ukrainian" ? "uk" : n === "russian" ? "ru" : "en";
  }

  // ---- words ---------------------------------------------------------------------

  function L(ctx, text) {
    if (!text) return "";
    return text[ctx.lang] || text.en || "";
  }
  function T(ctx, key, value) {
    var s = L(ctx, ctx.catalog.text[key]);
    return value === undefined ? s : s.replace("%@", value);
  }
  function key(v) { return JSON.stringify(v); }

  // ---- launch options from before the catalog (BACKLOG 21, P7A-6) ---------------

  // A renderer named in Steam's launch options (NOTPROTON_RENDERER, or CrossOver's
  // CX_GRAPHICS_BACKEND) moves into the catalog, and WINEMSYNC=1 (msync+ is on anyway)
  // goes. WINEMSYNC=0 and every other option stay; %command% stays where it was.
  function legacyOptions(options) {
    var parts = String(options || "").split(" ");
    var renderer = null, changed = false, kept = [];
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      var m = /^(NOTPROTON_RENDERER|CX_GRAPHICS_BACKEND)=(.*)$/.exec(p);
      if (m) {
        changed = true;
        var v = m[2].toLowerCase();
        if ((v === "dxmt" || v === "dxvk" || v === "wined3d") && (m[1] === "NOTPROTON_RENDERER" || !renderer)) renderer = v;
        continue;
      }
      if (p === "WINEMSYNC=1") { changed = true; continue; }
      kept.push(p);
    }
    if (!changed) return null;
    return { renderer: renderer, options: kept.filter(function (p, i) { return p || i > 0; }).join(" ").trim() };
  }

  // ---- one row --------------------------------------------------------------------

  function choiceOptions(ctx, choices) {
    return choices.map(function (c) { return { data: key(c.value), label: L(ctx, c.label) }; });
  }

  function help(ctx, s) {
    var h = s.help || {};
    return el("div", { className: "NPHelp" },
      el("div", null, L(ctx, h.summary)),
      (h.entries || []).length ? el("ul", null, h.entries.map(function (e, i) {
        return el("li", { key: i }, el("b", null, L(ctx, e.name)), " \u2014 ", L(ctx, e.text));
      })) : null,
      h.footnote ? el("div", { className: "NPFoot" }, L(ctx, h.footnote)) : null);
  }

  // The line under a row: what it inherits, or that the value is this level's own. One
  // button under the block resets them all (no Reset per row).
  function describe(ctx, s, v, info) {
    var line;
    if (v.own === null) {
      // A setting no level above sets (the renderer, msync+) names NotProton's default.
      var shared = !ctx.global && s.levels.indexOf("global") >= 0;
      line = T(ctx, shared ? "inherited" : "defaultValue", L(ctx, v.inheritedLabel));
    } else {
      line = T(ctx, ctx.global ? "ownGlobal" : "own");
    }
    return el("span", { className: "NPDesc" },
      s.caption ? el("span", { className: "NPCaption" }, L(ctx, s.caption)) : null,
      el("span", { className: "NPInherit" }, line),
      info ? help(ctx, s) : null);
  }

  function stop(e) {
    if (e && e.stopPropagation) e.stopPropagation();
    if (e && e.preventDefault) e.preventDefault();
  }

  function label(ctx, s, info, setInfo) {
    return el("span", { className: "NPLabel" },
      L(ctx, s.title),
      s.experimental ? el("span", { className: "NPExp" }, T(ctx, "experimental")) : null,
      el("span", {
        className: "NPInfo" + (info ? " NPOn" : ""), role: "button", "aria-label": "i",
        onClick: function (e) { stop(e); setInfo(!info); }
      }, "i"));
  }

  // Applies a typed number, or says it is not accepted.
  function NumberEditor(props) {
    var ctx = props.ctx, s = props.setting;
    var st = R.useState(String(props.value)), text = st[0], setText = st[1];
    var bad = R.useState(false), invalid = bad[0], setInvalid = bad[1];
    function apply() {
      var n = parseInt(text, 10), c = s.control;
      if (String(n) !== text.trim() || n < c.min || n > c.max) { setInvalid(true); return; }
      setInvalid(false);
      ctx.change(s.id, n);
    }
    return el("div", { className: "NPSub" },
      el(B.FO, {
        label: T(ctx, "fpsPlaceholder"), value: text,
        description: invalid ? T(ctx, "invalid") + " " + c2s(s.control) : c2s(s.control),
        onChange: function (e) { setText(e.target.value); },
        onBlur: apply,
        onKeyDown: function (e) { if (e.key === "Enter") apply(); }
      }));
  }
  function c2s(c) { return c.min + "\u2013" + c.max; }

  function TuningEditor(props) {
    var ctx = props.ctx, s = props.setting, v = props.value;
    var w = R.useState(String(v.waitSpin)), o = R.useState(String(v.objectSpin));
    function send(next) { ctx.change(s.id, next); }
    function num(t) { var n = parseInt(t, 10); return String(n) === String(t).trim() ? n : null; }
    function apply() {
      var a = num(w[0]), b = num(o[0]);
      if (a === null || b === null) return;
      send({ preset: "custom", waitSpin: a, adaptive: v.adaptive, objectSpin: b });
    }
    return el("div", { className: "NPSub" },
      el(B.FO, { label: T(ctx, "waitSpin"), value: w[0], onChange: function (e) { w[1](e.target.value); }, onBlur: apply }),
      el(B.FO, { label: T(ctx, "objectSpin"), value: o[0], onChange: function (e) { o[1](e.target.value); }, onBlur: apply }),
      el(B.y4, {
        label: T(ctx, "backOff"), checked: !!v.adaptive,
        onChange: function (on) { send({ preset: "custom", waitSpin: v.waitSpin, adaptive: !!on, objectSpin: v.objectSpin }); }
      }));
  }

  function GPUEditor(props) {
    var ctx = props.ctx, s = props.setting, v = props.value;
    function hex(n) { return n === undefined ? "" : ("0000" + Number(n).toString(16)).slice(-4); }
    var vendor = R.useState(hex(v.vendorID)), device = R.useState(hex(v.deviceID));
    var name = R.useState(v.name || ""), memory = R.useState(v.memoryMB === undefined ? "" : String(v.memoryMB));
    function apply() {
      var next = { preset: "custom", vendorID: vendor[0], deviceID: device[0], name: name[0] };
      var m = parseInt(memory[0], 10);
      if (String(m) === memory[0].trim()) next.memoryMB = m;
      ctx.change(s.id, next);
    }
    return el("div", { className: "NPSub" },
      el(B.FO, { label: T(ctx, "vendorID"), value: vendor[0], onChange: function (e) { vendor[1](e.target.value); } }),
      el(B.FO, { label: T(ctx, "deviceID"), value: device[0], onChange: function (e) { device[1](e.target.value); } }),
      el(B.FO, { label: T(ctx, "gpuName"), value: name[0], onChange: function (e) { name[1](e.target.value); } }),
      el(B.FO, { label: T(ctx, "memory"), value: memory[0], onChange: function (e) { memory[1](e.target.value); } }),
      el(B.$n, { onClick: apply }, T(ctx, "apply")));
  }

  function DLLEditor(props) {
    var ctx = props.ctx, s = props.setting, own = props.own || {};
    var modes = choiceOptions(ctx, s.control.choices);
    var n = R.useState(""), m = R.useState(modes[0].data);
    function put(next) { ctx.change(s.id, Object.keys(next).length ? next : null); }
    function with_(dll, mode) { var next = {}; for (var k in own) next[k] = own[k]; next[dll] = mode; return next; }
    return el("div", { className: "NPSub" },
      Object.keys(own).sort().map(function (dll) {
        return el("div", { key: dll, className: "NPListRow" },
          el("span", null, dll),
          el(B.m, { rgOptions: modes, selectedOption: key(own[dll]), onChange: function (o) { put(with_(dll, JSON.parse(o.data))); } }),
          el(B.$n, { onClick: function () { var next = with_(dll, ""); delete next[dll]; put(next); } }, T(ctx, "remove")));
      }),
      el("div", { className: "NPListRow" },
        el("input", { className: "NPInput", placeholder: T(ctx, "dllPlaceholder"), value: n[0], onChange: function (e) { n[1](e.target.value); } }),
        el(B.m, { rgOptions: modes, selectedOption: m[0], onChange: function (o) { m[1](o.data); } }),
        el(B.$n, { onClick: function () { if (n[0].trim()) { put(with_(n[0].trim(), JSON.parse(m[0]))); n[1](""); } } }, T(ctx, "add"))));
  }

  function EnvironmentEditor(props) {
    var ctx = props.ctx, s = props.setting;
    var t = R.useState((props.own || []).join("\n"));
    return el("div", { className: "NPSub" },
      el("textarea", {
        className: "NPArea", spellCheck: false, placeholder: T(ctx, "envPlaceholder"), value: t[0],
        onChange: function (e) { t[1](e.target.value); },
        onBlur: function () {
          var lines = t[0].split("\n").map(function (l) { return l.trim(); }).filter(function (l) { return l; });
          ctx.change(s.id, lines.length ? lines : null);
        }
      }));
  }

  // One setting as Steam draws a row of its kind.
  function Row(props) {
    var ctx = props.ctx, s = props.setting, v = ctx.state.values[s.id];
    var i = R.useState(false), info = i[0], setInfo = i[1];
    var c = R.useState(false), customOpen = c[0], setCustom = c[1];
    if (!v) return null;
    var lbl = label(ctx, s, info, setInfo), desc = describe(ctx, s, v, info);
    var ctl = s.control, eff = v.effective;
    switch (ctl.kind) {
      case "toggle":
        return el(B.y4, { label: lbl, description: desc, checked: eff === true, onChange: function (on) { ctx.change(s.id, !!on); } });
      case "choice":
        return el(B.Vb, {
          label: lbl, description: desc, rgOptions: choiceOptions(ctx, ctl.choices), selectedOption: key(eff),
          onChange: function (o) { ctx.change(s.id, JSON.parse(o.data)); }
        });
      case "limit": {
        var known = ctl.choices.some(function (ch) { return key(ch.value) === key(eff); });
        var opts = choiceOptions(ctx, ctl.choices).concat([{ data: key("__custom"), label: T(ctx, "customValue") }]);
        var custom = customOpen || !known;
        return el("div", null,
          el(B.Vb, {
            label: lbl, description: desc, rgOptions: opts, selectedOption: custom ? key("__custom") : key(eff),
            onChange: function (o) {
              var value = JSON.parse(o.data);
              if (value === "__custom") { setCustom(true); return; }
              setCustom(false);
              ctx.change(s.id, value);
            }
          }),
          custom ? el(NumberEditor, { ctx: ctx, setting: s, value: eff > 0 ? eff : 60, key: "n" + key(eff) }) : null);
      }
      case "tuning":
      case "gpu": {
        var preset = eff && eff.preset;
        return el("div", null,
          el(B.Vb, {
            label: lbl, description: desc, rgOptions: choiceOptions(ctx, ctl.choices), selectedOption: key(preset),
            onChange: function (o) { ctx.change(s.id, { preset: JSON.parse(o.data) }); }
          }),
          preset === "custom" ? el(ctl.kind === "tuning" ? TuningEditor : GPUEditor,
            { ctx: ctx, setting: s, value: eff, key: key(eff) }) : null);
      }
      case "dllOverrides":
        return el("div", { className: "NPBlock" },
          el(B.D0, { label: lbl, description: desc, bottomSeparator: "none" }),
          el(DLLEditor, { ctx: ctx, setting: s, own: v.own, key: key(v.own) }));
      case "environment":
        return el("div", { className: "NPBlock" },
          el(B.D0, { label: lbl, description: desc, bottomSeparator: "none" }),
          el(EnvironmentEditor, { ctx: ctx, setting: s, own: v.own, key: key(v.own) }));
      default:
        return null;
    }
  }

  // ---- the views (pure: tests render them from a fixed context) ------------------

  function rows(ctx, list) {
    return list.map(function (s) { return el(Row, { key: s.id, ctx: ctx, setting: s }); });
  }

  function settingsAt(ctx, quick) {
    var level = ctx.global ? "global" : "game";
    return ctx.catalog.settings.filter(function (s) {
      return s.levels.indexOf(level) >= 0 && (quick ? s.quick !== undefined : s.quick === undefined);
    }).sort(function (a, b) { return (a.quick || 0) - (b.quick || 0); });
  }

  function statusLine(ctx) {
    var st = ctx.state;
    if (ctx.global) return el("div", { className: "NPStatus" }, T(ctx, "globalApplies"));
    var line = st.status === "restartGame" ? T(ctx, "restartGame")
      : st.status === "firstLaunch" ? T(ctx, "firstLaunch") : T(ctx, "nextLaunch");
    return el("div", { className: "NPStatus" + (st.status === "restartGame" ? " NPWarn" : "") },
      line,
      st.exes && st.exes.length ? el("div", null, T(ctx, "executables", st.exes.join(", "))) : null);
  }

  // The Advanced dialog goes into the window's own body through a portal: a page's
  // container can be a containing block for fixed elements (Settings > Compatibility is),
  // which would pin the dialog inside the page and cut it. Without React DOM it stays inline.
  function overlay(ctx) {
    var d = dialog(ctx);
    return D && typeof D.createPortal === "function" && ctx.host ? D.createPortal(d, ctx.host) : d;
  }

  function view(ctx) {
    if (MISSING.length) {
      var lang = FALLBACK[ctx.lang] ? ctx.lang : "en";
      return el("div", { className: "NPPanel" }, style(),
        el("div", { className: "NPError" }, FALLBACK[lang].replace("%@", "Steam UI (" + MISSING.join(", ") + ")")));
    }
    if (ctx.error && !ctx.state) {
      var fb = FALLBACK[ctx.lang] || FALLBACK.en;
      return el("div", { className: "NPPanel" }, style(), el("div", { className: "NPError" }, fb.replace("%@", ctx.error)));
    }
    if (!ctx.catalog || !ctx.state) return el("div", { className: "NPPanel" }, style());
    var title = ctx.global ? T(ctx, "globalSection") : T(ctx, "section");
    var engine = ctx.state.engine ? ctx.state.engine.replace(/^dormison-/, "Dormison ") : "";
    return el("div", { className: "NPPanel", ref: ctx.hostRef },
      style(),
      el("div", { className: "NPHeader" }, el("b", null, title), engine ? el("span", null, engine) : null),
      ctx.global ? el("div", { className: "NPCaption NPTop" }, T(ctx, "globalCaption")) : null,
      rows(ctx, settingsAt(ctx, true)),
      el("div", { className: "NPActions" },
        el(B.$n, { onClick: function () { ctx.setAdvanced(true); } }, T(ctx, "advanced")),
        el(B.$n, { className: "NPReset", onClick: function () { ctx.reset(); } },
          T(ctx, ctx.global ? "resetGlobal" : "resetGame"))),
      statusLine(ctx),
      ctx.error ? el("div", { className: "NPError" }, T(ctx, "saveFailed", ctx.error)) : null,
      ctx.advanced ? overlay(ctx) : null);
  }

  // The Advanced dialog: every other row of the level, by group, over the window.
  function dialog(ctx) {
    var level = ctx.global ? "global" : "game";
    var others = settingsAt(ctx, false);
    var title = ctx.global ? T(ctx, "advancedGlobalTitle") : T(ctx, "advancedTitle", ctx.state.name || ("App " + ctx.state.appID));
    var close = function () { ctx.setAdvanced(false); };
    return el("div", {
      className: "NPOverlay", tabIndex: -1,
      ref: function (node) { if (node && !node.contains(node.ownerDocument.activeElement)) node.focus(); },
      onKeyDown: function (e) { if (e.key === "Escape") { stop(e); close(); } },
      onMouseDown: function (e) { if (e.target === e.currentTarget) close(); }
    },
      style(),
      el("div", { className: "NPDialog DialogContent", role: "dialog", "aria-label": title },
        el("div", { className: "NPDialogHead" }, title),
        el("div", { className: "NPDialogBody" },
          ctx.catalog.groups.map(function (g) {
            var list = others.filter(function (s) { return s.group === g.id; });
            if (!list.length) return null;
            return el("div", { key: g.id, className: "NPGroupBox" },
              el("div", { className: "NPGroup" }, L(ctx, g.title)),
              rows(ctx, list));
          })),
        el("div", { className: "NPDialogFoot" },
          el(B.$n, { onClick: function () { ctx.reset(); } }, T(ctx, ctx.global ? "resetGlobal" : "resetGame")),
          ctx.error ? el("span", { className: "NPError" }, T(ctx, "saveFailed", ctx.error)) : null,
          el(B.$n, { className: "NPPrimary", onClick: close }, T(ctx, "done")))));
  }

  var CSS =
    ".NPPanel{margin-top:16px}" +
    ".NPHeader{display:flex;justify-content:space-between;align-items:baseline;margin:8px 0 2px;color:#fff}" +
    ".NPHeader b{font-size:13px;letter-spacing:.06em;text-transform:uppercase}" +
    ".NPHeader span{color:#8b929a;font-size:12px}" +
    ".NPTop{display:block;margin-bottom:6px;font-size:13px}" +
    ".NPLabel{display:inline-flex;align-items:center;gap:6px}" +
    ".NPInfo{display:inline-block;width:14px;height:14px;border-radius:50%;border:1px solid #8b929a;color:#8b929a;" +
    "font:italic 10px/13px serif;text-align:center;cursor:pointer;flex:none}" +
    ".NPInfo.NPOn,.NPInfo:hover{border-color:#1a9fff;color:#1a9fff}" +
    ".NPExp{font-size:11px;color:#e4c046}" +
    ".NPDesc{display:flex;flex-direction:column;gap:2px}" +
    ".NPCaption{color:#8b929a}" +
    ".NPInherit{color:#8b929a}" +
    ".NPLink{color:#1a9fff;cursor:pointer}" +
    ".NPHelp{margin-top:6px;padding:8px 10px;background:rgba(0,0,0,.25);border-radius:3px;color:#c7d5e0;white-space:normal}" +
    ".NPHelp ul{margin:6px 0 0;padding-left:16px}.NPHelp b{color:#fff}.NPFoot{margin-top:6px;color:#8b929a}" +
    ".NPSub{padding:4px 0 8px 16px}" +
    ".NPActions{margin-top:12px;display:flex;flex-direction:column;gap:8px}" +
    ".NPStatus{color:#8b929a;font-size:12px;margin-top:8px}.NPStatus.NPWarn{color:#e4c046}" +
    ".NPError{color:#ff7b7b;font-size:12px;margin-top:8px}" +
    ".NPOverlay{position:fixed;left:0;top:0;right:0;bottom:0;z-index:1500;background:rgba(0,0,0,.65);" +
    "display:flex;align-items:center;justify-content:center;outline:none}" +
    ".NPDialog{background:#23262e;width:min(660px,92vw);max-height:86vh;display:flex;flex-direction:column;" +
    "border-radius:4px;box-shadow:0 12px 40px rgba(0,0,0,.7)}" +
    ".NPDialogHead{padding:20px 24px 12px;font-size:22px;color:#fff;border-bottom:1px solid rgba(255,255,255,.1)}" +
    ".NPDialogBody{padding:0 24px 8px;overflow-y:auto}" +
    ".NPDialogFoot{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:14px 24px 18px;" +
    "border-top:1px solid rgba(255,255,255,.1)}" +
    ".NPGroup{margin:18px 0 4px;font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#fff}" +
    ".NPInput,.NPArea{background:#32363f;color:#fff;border:1px solid #3d4450;border-radius:3px;padding:6px 8px;" +
    "font-size:13px;box-sizing:border-box}" +
    ".NPInput{flex:1;min-width:0;height:34px}" +
    ".NPArea{display:block;width:100%;min-height:84px;font-family:Menlo,monospace;resize:vertical}" +
    ".NPBlock .NPSub{padding:0 0 12px}" +
    ".NPListRow{display:flex;gap:8px;align-items:center;margin:4px 0}.NPListRow>span{flex:1;color:#dcdedf}" +
    ".NPListRow>*:not(span):not(input){flex:none;margin-top:0!important;margin-bottom:0!important}" +
    ".NPListRow button{width:auto!important;min-width:96px;padding:0 16px!important;height:34px}" +
    ".NPPrimary{background:linear-gradient(90deg,#1a9fff,#1474e0)!important;color:#fff!important}";
  function style() { return el("style", null, CSS); }

  // ---- the components the page renders --------------------------------------------

  function usePanel(appID, details, enabled) {
    var l = R.useState("en"), c = R.useState(null), s = R.useState(null), e = R.useState(null), a = R.useState(false);
    var h = R.useState(null);
    R.useEffect(function () {
      if (!enabled) return undefined;
      var live = true;
      Promise.all([language(), loadCatalog(), ask({ op: "state", app: appID })]).then(function (r) {
        if (!live) return;
        l[1](r[0]);
        if (!r[1].ok) { e[1](r[1].error); return; }
        c[1](r[1].catalog);
        if (!r[2].ok) { e[1](r[2].error); return; }
        s[1](r[2].state);
        var legacy = details ? legacyOptions(details.strLaunchOptions) : null;
        if (legacy) migrateOptions(appID, legacy, r[2].state, s[1]);
      });
      return function () { live = false; };
    }, [appID, enabled]);
    function answered(r) {
      if (r.ok) { s[1](r.state); e[1](null); } else { e[1](r.error); }
    }
    return {
      lang: l[0], catalog: c[0], state: s[0], error: e[0], advanced: a[0], setAdvanced: a[1],
      host: h[0],
      hostRef: function (node) {
        var body = node && node.ownerDocument ? node.ownerDocument.body : null;
        if (body !== h[0]) h[1](body);
      },
      global: appID === undefined,
      change: function (id, value) { return ask({ op: "set", app: appID, id: id, value: value }).then(answered); },
      reset: function () { return ask({ op: "reset", app: appID }).then(answered); }
    };
  }

  // The launch options' renderer becomes the game's own (it was the one in force),
  // then the options lose it.
  function migrateOptions(appID, legacy, state, setState) {
    var write = legacy.renderer
      ? ask({ op: "set", app: appID, id: "renderer", value: legacy.renderer })
      : Promise.resolve({ ok: true, state: state });
    write.then(function (r) {
      if (!r.ok) return;
      setState(r.state);
      SteamClient.Apps.SetAppLaunchOptions(appID, legacy.options);
    });
  }

  // Steam's own apps, non-Steam shortcuts included, that run through NotProton: a forced
  // NotProton, or no forced tool on a game without a macOS build.
  function runsThroughNotProton(d) {
    if (!d) return false;
    var tool = d.strCompatToolName || "";
    if (tool) return tool === "notproton";
    return (d.vecPlatforms || []).indexOf("osx") < 0;
  }

  function GamePanel(props) {
    var d = props.details, on = runsThroughNotProton(d);
    if (MISSING.indexOf("React") >= 0) return on ? view({ lang: "en" }) : null;
    var ctx = usePanel(d ? d.unAppID : 0, d, on);
    return on ? view(ctx) : null;
  }

  function GlobalPanel() {
    if (MISSING.indexOf("React") >= 0) return view({ lang: "en" });
    return view(usePanel(undefined, null, true));
  }

  return {
    Game: GamePanel, Global: GlobalPanel,
    // For the fixture tests.
    view: view, legacyOptions: legacyOptions, requestPath: requestPath, langOf: langOf,
    runsThroughNotProton: runsThroughNotProton, FALLBACK: FALLBACK
  };
})
