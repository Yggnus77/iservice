// uso: node render.js entrada.svg saida.png largura [altura]
const {chromium}=require('playwright');
(async()=>{const a=process.argv.slice(2);const b=await chromium.launch();
for(let i=0;i<a.length;i+=4){const [src,out,w,h]=a.slice(i,i+4);
const p=await b.newPage({viewport:{width:+w,height:+h}});
const svg=require('fs').readFileSync(src,'utf8');
await p.setContent(`<html><body style="margin:0;background:transparent"><img src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}" style="display:block;width:${w}px;height:${h}px"></body></html>`);
await p.waitForFunction(()=>document.images[0].complete);
await p.screenshot({path:out,omitBackground:true});await p.close();}
await b.close();})();
