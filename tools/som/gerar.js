// Gera o som da marca a partir de config.json e grava os WAV mestres.
// Uso: node tools/som/gerar.js   (depois converta: ogg para Android, caf para iPhone; ver README.md)
const { sintetizar } = require('./synth.js');
const fs = require('fs');
const path = require('path');
const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
function wav(nome, d, sr) {
  const b = Buffer.alloc(44 + d.length * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + d.length * 2, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(sr, 24);
  b.writeUInt32LE(sr * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(d.length * 2, 40);
  for (let i = 0; i < d.length; i++) b.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(d[i] * 32767))), 44 + i * 2);
  fs.writeFileSync(path.join(__dirname, nome), b);
}
wav('iservice_som_cliente.wav', sintetizar(cfg, 44100, false), 44100);
wav('iservice_som_profissional.wav', sintetizar(cfg, 44100, true), 44100);
console.log('ok');
