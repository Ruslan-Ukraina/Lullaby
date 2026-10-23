// webpatch-syntax: the selecttool page's panel finds React through webpack's runtime
// (LBSelP in dylib/feats/webpatch.c): from the module cache, from the factories, and
// null without webpack (the renderer list stays).
const fs=require("fs");const src=fs.readFileSync(process.argv[2],"utf8");
const i=src.indexOf('function LBSelP(');const j=src.indexOf('return LBSelP.p}',i)+'return LBSelP.p}'.length;
const code=src.slice(i,j);
function run(cache){
  const React={useState:()=>[0,()=>{}],useEffect:()=>{},createElement:()=>{}};
  const q=function(k){return q.mods[k]};q.mods={1:React,2:{createPortal:()=>{}}};
  if(cache)q.c={1:{exports:React},2:{exports:{createPortal:()=>{}}}};
  q.m={1:function(){/* x.useState=1;x.createElement=1 */},2:function(){/* x.createPortal=1 */}};
  global.self={webpackChunksteamui:{push:(a)=>a[2](q)}};
  const f=new Function('return ('+code+')')();
  const B={y4:{},Vb:{},FO:{},$n:{},D0:{}};
  const p=f({jsx:()=>null,jsxs:()=>null},B);return p&&typeof p.Game==='function'&&typeof p.Global==='function';
}
if (i < 0) process.exit(0); // a chunk without the selecttool page
const ok=run(true)&&run(false);
global.self={};const none=new Function('return ('+code+')')()({},{});
if(!ok||none!==null){console.error('lbselp-check: React finder failed');process.exit(1);}
