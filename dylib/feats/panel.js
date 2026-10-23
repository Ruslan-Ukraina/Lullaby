// Lullaby's settings in Steam (docs/ROADMAP.md section 5): the block under Properties >
// Compatibility (a game's own values) and under Settings > Compatibility (values for all
// games), each with its quick rows and an Advanced dialog, drawn with Steam's own controls.
//
// The webpatch puts this function expression into the page twice and calls it with the
// names the page's module gives React's JSX runtime (J), Steam's dialog controls (B),
// React (R) and React DOM (D, may be null). Everything the panel shows comes from the catalog lullaby-settings answers
// with (LullabySettings): it names no setting, key or text of its own, except the three
// lines below for when the catalog cannot be reached. Requests travel as virtual files
// under steamloopback.host (dylib/feats/settingsbridge.c); the dylib puts its token in.
//
// Kept to ASCII: dylib/embed_js.py embeds it as a C string.
(function (J, B, R, D) {
  "use strict";
  var TOKEN = "__NP_SETTINGS_TOKEN__";
  var FALLBACK = {
    en: "Lullaby settings are unavailable: %@",
    uk: "\u041d\u0430\u043b\u0430\u0448\u0442\u0443\u0432\u0430\u043d\u043d\u044f Lullaby \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u0456: %@",
    ru: "\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 Lullaby \u043d\u0435\u0434\u043e\u0441\u0442\u0443\u043f\u043d\u044b: %@"
  };
  var DOT = " \u00b7 ";
  // Steam's controls the panel draws with. Their names are the page's own and not part of
  // the webpatch anchors, so a Steam update can rename one; the panel then says so rather
  // than take the Properties page down with it.
  var MISSING = ["y4", "Vb", "FO", "$n", "D0"].filter(function (k) {
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
    return "/lullaby-settings/" + TOKEN + "/" + Date.now().toString(36) + seq.toString(36) + "/" +
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

  // ---- one row --------------------------------------------------------------------

  // A choice that needs a component the player has not added (D3DMetal) is not offered.
  function available(ctx, c) {
    return !c.requires || (c.requires === "d3dmetal" && !!toolkit(ctx).active);
  }
  function toolkit(ctx) { return (ctx.state && ctx.state.d3dmetal) || {}; }
  function choiceOptions(ctx, choices) {
    return choices.filter(function (c) { return available(ctx, c); })
      .map(function (c) { return { data: key(c.value), label: L(ctx, c.label) }; });
  }

  function help(ctx, s) {
    var h = s.help || {};
    return el("div", { className: "LBHelp" },
      el("div", null, L(ctx, h.summary)),
      (h.entries || []).length ? el("ul", null, h.entries.map(function (e, i) {
        return el("li", { key: i }, el("b", null, L(ctx, e.name)), " \u2014 ", L(ctx, e.text));
      })) : null,
      h.footnote ? el("div", { className: "LBFoot" }, L(ctx, h.footnote)) : null);
  }

  // The line under a row names what the level above holds, and only where this level's
  // value differs from it (a value equal to it is stored as inherit): "For all games" on a
  // game's page, Lullaby's default for all games and for a game's own rows (the
  // renderer, msync+). One button under the block resets them all.
  // A value Lullaby's recipe supplies (DECISIONS A1010-3) is named as the recipe's, both
  // when the game follows it and when its own choice differs from it.
  function describe(ctx, s, v, info) {
    var line = null;
    if (v.own !== null) {
      var shared = !ctx.global && s.levels.indexOf("global") >= 0;
      line = v.inheritedFrom === "recipe" ? T(ctx, "recipeValue", L(ctx, v.inheritedLabel))
        : T(ctx, shared ? "inherited" : "defaultValue", L(ctx, v.inheritedLabel));
    } else if (!ctx.global && v.inheritedFrom === "recipe") {
      line = T(ctx, "recipe");
    }
    return el("span", { className: "LBDesc" },
      s.caption ? el("span", { className: "LBCaption" }, L(ctx, s.caption)) : null,
      line ? el("span", { className: "LBInherit" }, line) : null,
      info ? help(ctx, s) : null);
  }

  function resetLabel(ctx) {
    return ctx.global ? "resetGlobal" : (ctx.state && ctx.state.recipe ? "resetRecipe" : "resetGame");
  }

  function stop(e) {
    if (e && e.stopPropagation) e.stopPropagation();
    if (e && e.preventDefault) e.preventDefault();
  }

  function label(ctx, s, info, setInfo) {
    return el("span", { className: "LBLabel" },
      L(ctx, s.title),
      s.experimental ? el("span", { className: "LBExp" }, T(ctx, "experimental")) : null,
      el("span", {
        className: "LBInfo" + (info ? " LBOn" : ""), role: "button", "aria-label": "i",
        onClick: function (e) { stop(e); setInfo(!info); }
      }, "i"));
  }

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
    return el("div", { className: "LBSub" },
      el(B.FO, { label: T(ctx, "waitSpin"), value: w[0], onChange: function (e) { w[1](e.target.value); }, onBlur: apply }),
      el(B.FO, { label: T(ctx, "objectSpin"), value: o[0], onChange: function (e) { o[1](e.target.value); }, onBlur: apply }),
      el(B.y4, {
        label: T(ctx, "backOff"), checked: !!v.adaptive,
        onChange: function (on) { send({ preset: "custom", waitSpin: v.waitSpin, adaptive: !!on, objectSpin: v.objectSpin }); }
      }));
  }

  // One setting as Steam draws a row of its kind. A list is as wide as its choices
  // (Steam's own "min" width), not a fixed share of the row.
  function Row(props) {
    var ctx = props.ctx, s = props.setting, v = ctx.state.values[s.id];
    var i = R.useState(false), info = i[0], setInfo = i[1];
    if (!v) return null;
    var lbl = label(ctx, s, info, setInfo), desc = describe(ctx, s, v, info);
    var ctl = s.control, eff = v.effective;
    switch (ctl.kind) {
      case "toggle":
        return el(B.y4, { label: lbl, description: desc, checked: eff === true, onChange: function (on) { ctx.change(s.id, !!on); } });
      case "choice": {
        var list = el(B.Vb, {
          label: lbl, description: desc, rgOptions: choiceOptions(ctx, ctl.choices), selectedOption: key(eff),
          childrenContainerWidth: "min",
          onChange: function (o) { ctx.change(s.id, JSON.parse(o.data)); }
        });
        // D3DMetal picked (by the player or a recipe) but no toolkit added: one line
        // pointing to Lullaby's settings, where the toolkit is added (Phase 8).
        var needsToolkit = !toolkit(ctx).active && ctl.choices.some(function (c) {
          return c.requires === "d3dmetal" && key(c.value) === key(eff);
        });
        return needsToolkit ? el("div", null, list,
          el("div", { className: "LBStatus LBWarn" }, T(ctx, "toolkitInSettings"))) : list;
      }
      case "tuning": {
        var preset = eff && eff.preset;
        return el("div", null,
          el(B.Vb, {
            label: lbl, description: desc, rgOptions: choiceOptions(ctx, ctl.choices), selectedOption: key(preset),
            childrenContainerWidth: "min",
            onChange: function (o) { ctx.change(s.id, { preset: JSON.parse(o.data) }); }
          }),
          preset === "custom" ? el(TuningEditor, { ctx: ctx, setting: s, value: eff, key: key(eff) }) : null);
      }
      default:
        return null;
    }
  }

  // ---- the views (pure: tests render them from a fixed context) ------------------

  function rows(ctx, list) {
    return list.map(function (s) { return el(Row, { key: s.id, ctx: ctx, setting: s }); });
  }

  // A row for some renderers only (MetalFX: DXMT) is drawn for a game on one of them.
  function shownWithRenderer(ctx, s) {
    if (ctx.global || !s.renderers || !s.renderers.length) return true;
    var r = ctx.state && ctx.state.values && ctx.state.values.renderer;
    return !r || s.renderers.indexOf(r.effective) >= 0;
  }

  function settingsAt(ctx, quick) {
    var level = ctx.global ? "global" : "game";
    return ctx.catalog.settings.filter(function (s) {
      return s.levels.indexOf(level) >= 0 && (quick ? s.quick !== undefined : s.quick === undefined)
        && shownWithRenderer(ctx, s);
    }).sort(function (a, b) { return (a.quick || 0) - (b.quick || 0); });
  }

  function statusLine(ctx) {
    var st = ctx.state;
    if (ctx.global) return el("div", { className: "LBStatus" }, T(ctx, "globalApplies"));
    var line = st.status === "restartGame" ? T(ctx, "restartGame")
      : st.status === "firstLaunch" ? T(ctx, "firstLaunch") : T(ctx, "nextLaunch");
    return el("div", { className: "LBStatus" + (st.status === "restartGame" ? " LBWarn" : "") },
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
      return el("div", { className: "LBPanel" }, style(),
        el("div", { className: "LBError" }, FALLBACK[lang].replace("%@", "Steam UI (" + MISSING.join(", ") + ")")));
    }
    if (ctx.error && !ctx.state) {
      var fb = FALLBACK[ctx.lang] || FALLBACK.en;
      return el("div", { className: "LBPanel" }, style(), el("div", { className: "LBError" }, fb.replace("%@", ctx.error)));
    }
    if (!ctx.catalog || !ctx.state) return el("div", { className: "LBPanel" }, style());
    var title = ctx.global ? T(ctx, "globalSection") : T(ctx, "section");
    return el("div", { className: "LBPanel", ref: ctx.hostRef },
      style(),
      el("div", { className: "LBHeader" }, el("b", null, title)),
      ctx.global ? el("div", { className: "LBCaption LBTop" }, T(ctx, "globalCaption")) : null,
      rows(ctx, settingsAt(ctx, true)),
      el("div", { className: "LBActions" },
        el(B.$n, { onClick: function () { ctx.setAdvanced(true); } }, T(ctx, "advanced")),
        el(B.$n, { className: "LBReset", onClick: function () { ctx.reset(); } },
          T(ctx, resetLabel(ctx)))),
      statusLine(ctx),
      ctx.error ? el("div", { className: "LBError" }, T(ctx, "saveFailed", ctx.error)) : null,
      ctx.advanced ? overlay(ctx) : null);
  }

  // The Advanced dialog: every other row of the level, by group, over the window.
  function dialog(ctx) {
    var level = ctx.global ? "global" : "game";
    var others = settingsAt(ctx, false);
    var title = ctx.global ? T(ctx, "advancedGlobalTitle") : T(ctx, "advancedTitle", ctx.state.name || ("App " + ctx.state.appID));
    var close = function () { ctx.setAdvanced(false); };
    return el("div", {
      className: "LBOverlay", tabIndex: -1,
      ref: function (node) { if (node && !node.contains(node.ownerDocument.activeElement)) node.focus(); },
      onKeyDown: function (e) { if (e.key === "Escape") { stop(e); close(); } },
      onMouseDown: function (e) { if (e.target === e.currentTarget) close(); }
    },
      style(),
      el("div", { className: "LBDialog DialogContent", role: "dialog", "aria-label": title },
        el("div", { className: "LBDialogHead" }, title),
        el("div", { className: "LBDialogBody" },
          ctx.catalog.groups.map(function (g) {
            var list = others.filter(function (s) { return s.group === g.id; });
            if (!list.length) return null;
            return el("div", { key: g.id, className: "LBGroupBox" },
              el("div", { className: "LBGroup" }, L(ctx, g.title)),
              rows(ctx, list));
          })),
        el("div", { className: "LBDialogFoot" },
          el(B.$n, { onClick: function () { ctx.reset(); } }, T(ctx, resetLabel(ctx))),
          ctx.error ? el("span", { className: "LBError" }, T(ctx, "saveFailed", ctx.error)) : null,
          el(B.$n, { className: "LBPrimary", onClick: close }, T(ctx, "done")))));
  }

  var CSS =
    ".LBPanel{margin-top:16px}" +
    ".LBHeader{display:flex;justify-content:space-between;align-items:baseline;margin:8px 0 2px;color:#fff}" +
    ".LBHeader b{font-size:13px;letter-spacing:.06em;text-transform:uppercase}" +
    ".LBTop{display:block;margin-bottom:6px;font-size:13px}" +
    ".LBLabel{display:inline-flex;align-items:center;gap:6px}" +
    ".LBInfo{display:inline-block;width:14px;height:14px;border-radius:50%;border:1px solid #8b929a;color:#8b929a;" +
    "font:italic 10px/13px serif;text-align:center;cursor:pointer;flex:none}" +
    ".LBInfo.LBOn,.LBInfo:hover{border-color:#1a9fff;color:#1a9fff}" +
    ".LBExp{font-size:11px;color:#e4c046}" +
    ".LBDesc{display:flex;flex-direction:column;gap:2px}" +
    ".LBCaption{color:#8b929a}" +
    ".LBInherit{color:#8b929a}" +
    ".LBLink{color:#1a9fff;cursor:pointer}" +
    ".LBHelp{margin-top:6px;padding:8px 10px;background:rgba(0,0,0,.25);border-radius:3px;color:#c7d5e0;white-space:normal}" +
    ".LBHelp ul{margin:6px 0 0;padding-left:16px}.LBHelp b{color:#fff}.LBFoot{margin-top:6px;color:#8b929a}" +
    ".LBSub{padding:4px 0 8px 16px}" +
    ".LBActions{margin-top:12px;display:flex;flex-direction:column;gap:8px}" +
    ".LBStatus{color:#8b929a;font-size:12px;margin-top:8px}.LBStatus.LBWarn{color:#e4c046}" +
    ".LBError{color:#ff7b7b;font-size:12px;margin-top:8px}" +
    ".LBOverlay{position:fixed;left:0;top:0;right:0;bottom:0;z-index:1500;background:rgba(0,0,0,.65);" +
    "display:flex;align-items:center;justify-content:center;outline:none}" +
    ".LBDialog{background:#23262e;width:min(660px,92vw);max-height:86vh;display:flex;flex-direction:column;" +
    "border-radius:4px;box-shadow:0 12px 40px rgba(0,0,0,.7)}" +
    ".LBDialogHead{padding:20px 24px 12px;font-size:22px;color:#fff;border-bottom:1px solid rgba(255,255,255,.1)}" +
    ".LBDialogBody{padding:0 24px 8px;overflow-y:auto}" +
    ".LBDialogFoot{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:14px 24px 18px;" +
    "border-top:1px solid rgba(255,255,255,.1)}" +
    ".LBGroup{margin:18px 0 4px;font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#fff}" +
    // Steam's .DialogContent draws lists larger (16px, 12px padding) than the Properties
    // page around the dialog does; the dialog's lists match the page's.
    ".LBDialog .DialogDropDown{font-size:13px;padding:8px 14px;line-height:18px}" +
    ".LBPrimary{background:linear-gradient(90deg,#1a9fff,#1474e0)!important;color:#fff!important}";
  function style() { return el("style", null, CSS); }

  // ---- the components the page renders --------------------------------------------

  function usePanel(appID, enabled) {
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

  // Steam's own apps, non-Steam shortcuts included, that run through Lullaby: a forced
  // Lullaby, or no forced tool on a game without a macOS build.
  function runsThroughLullaby(d) {
    if (!d) return false;
    var tool = d.strCompatToolName || "";
    if (tool) return tool === "lullaby";
    return (d.vecPlatforms || []).indexOf("osx") < 0;
  }

  function GamePanel(props) {
    var d = props.details, on = runsThroughLullaby(d);
    if (MISSING.indexOf("React") >= 0) return on ? view({ lang: "en" }) : null;
    var ctx = usePanel(d ? d.unAppID : 0, on);
    return on ? view(ctx) : null;
  }

  function GlobalPanel() {
    if (MISSING.indexOf("React") >= 0) return view({ lang: "en" });
    return view(usePanel(undefined, true));
  }

  return {
    Game: GamePanel, Global: GlobalPanel,
    // For the fixture tests.
    view: view, requestPath: requestPath, langOf: langOf,
    runsThroughLullaby: runsThroughLullaby, FALLBACK: FALLBACK
  };
})
