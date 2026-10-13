import assert from 'node:assert/strict';
import { build } from 'vite';
const result=await build({configFile:false,logLevel:'silent',build:{write:false,minify:false,lib:{entry:'src/lib/paymentProviders.ts',formats:['es']}}});
const {normalizePaymentUrl:parse}=await import(`data:text/javascript;base64,${Buffer.from((Array.isArray(result)?result[0]:result).output.find(i=>i.type==='chunk').code).toString('base64')}`);
let count=0;
for(const [provider,url,expected] of [
 ['monzo',' HTTPS://MONZO.ME/example?ref=Case%20Kept#Fragment ','https://monzo.me/example?ref=Case%20Kept#Fragment'],
 ['revolut','https://revolut.me/example','https://revolut.me/example'],
 ['paypal','HTTPS://PAYPAL.ME/Example','https://paypal.me/Example'],
 ['custom','https://pay.example.com/Case?amount=12#ref','https://pay.example.com/Case?amount=12#ref']
]){assert.equal(parse(provider,url),expected);count++;}
for(const [provider,url] of [
 ...['http://paypal.me/Example','https://paypal.me.evil.com/Example','https://evil.com/Example','https://paypal.me/','https://paypal.me/Example/50','https://paypal.me/Example?ref=foo','https://paypal.me/Example#foo','https://paypal.me/with-dash','https://paypal.me/'+ 'a'.repeat(21)].map(url=>['paypal',url]),
 ['monzo','http://monzo.me/example'],['monzo','https://monzo.me.evil.com/example'],['monzo','https://evil.com/?next=https://monzo.me/example'],['revolut','https://monzo.me/example'],['monzo','https://monzo.me/'],
 ...['javascript:alert(1)','data:text/html,hi','','https://127.0.0.1/path','https://10.0.0.1/path','https://172.16.1.1/path','https://192.168.1.1/path','https://169.254.169.254/path','https://[::1]/path','https://2130706433/path','https://0x7f000001/path','https://localhost/path','https://example.local/path','https://example.com:443/path','https://user:pass@example.com/path','https://example..com/path','https://-bad.example.com/path','https://example.com\\@monzo.me/path','https://example.com/%zz','https://example.com/a b','https://example.com/\nfoo','https://example.com/'+ 'x'.repeat(2048)].map(url=>['custom',url])
]){assert.throws(()=>parse(provider,url));count++;}
console.log(`PASS payment URL frontend policy: ${count} cases; no network requests.`);
