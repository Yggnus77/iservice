// Motor de síntese do sino iService. O mesmo código roda na página e no Node (para gerar os arquivos finais).
const TIMBRES = {
  latao:   { nome: 'Sino de latão',      modos: [[1,1,1.0],[1.505,.42,.7],[2.04,.55,.6],[2.67,.28,.42],[3.38,.32,.3],[4.12,.18,.22],[4.95,.15,.16],[5.82,.09,.12],[6.8,.06,.09]] },
  vidro:   { nome: 'Sino de vidro',      modos: [[1,1,1.0],[2.756,.38,.45],[5.404,.18,.2],[8.933,.08,.1]] },
  caixinha:{ nome: 'Caixinha de música', modos: [[1,1,1.0],[3.01,.12,.25],[6.27,.22,.12],[17.55,.05,.03]] },
  tigela:  { nome: 'Tigela de metal',    modos: [[1,1,1.0],[2.71,.5,.8],[5.12,.25,.5],[8.3,.1,.3]] },
  hotel:   { nome: 'Sino de balcão',     modos: [[1,1,1.0],[2.32,.5,.6],[4.25,.35,.35],[6.63,.2,.2],[9.38,.1,.12]] },
};
const MELODIAS = {
  uma:      { nome: 'Uma nota',                 notas: [0] },
  sobe4:    { nome: 'Duas notas subindo',       notas: [0, 5] },
  desce3:   { nome: 'Duas notas descendo',      notas: [4, 0] },
  sobe5:    { nome: 'Duas notas, salto grande', notas: [0, 7] },
  iservice: { nome: 'Três notas: i-ser-vice',   notas: [0, 4, 7] },
  volta:    { nome: 'Três notas, volta',        notas: [7, 4, 12] },
  quatro:   { nome: 'Quatro notas',             notas: [0, 7, 4, 12] },
};
const PADRAO = { timbre: 'latao', melodia: 'sobe4', tom: 1600, espaco: 160, batidas: 1, badalo: 90, suavidade: 0.7, duracao: 1.0, brilho: 0.4, eco: 0.25, tremor: 0.0, oitava: 0 };

function rng(seed) { let s = seed >>> 0 || 1; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }

function sintetizar(p, sr = 44100, profissional = false) {
  p = Object.assign({}, PADRAO, p);
  const rand = rng(12345);
  const timbre = TIMBRES[p.timbre] || TIMBRES.latao;
  const notas = (MELODIAS[p.melodia] || MELODIAS.uma).notas;
  const base = p.tom * Math.pow(2, p.oitava || 0);
  // eventos: [tempo, freq, força]
  const ev = [];
  const frase = (t0, forca, transp) => {
    notas.forEach((n, i) => {
      const f = base * Math.pow(2, (n + transp) / 12);
      const tn = t0 + i * p.espaco / 1000;
      let v = forca * (i === notas.length - 1 ? 1 : 0.85);
      for (let b = 0; b < p.batidas; b++) {
        ev.push([tn + b * (p.badalo / 1000) * (1 + 0.3 * b) * (0.9 + 0.2 * rand()), f, v]);
        v *= 0.62;
      }
    });
  };
  const fraseDur = (notas.length - 1) * p.espaco / 1000 + (p.batidas - 1) * p.badalo / 1000 * 1.5;
  frase(0.01, 1, 0);
  if (profissional) frase(0.01 + Math.max(0.55, fraseDur + 0.35), 1, 0);
  const fim = Math.max(...ev.map(e => e[0])) + p.duracao * 1.6 + 0.15;
  const N = Math.ceil(fim * sr);
  const out = new Float32Array(N);
  const dureza = 1 - p.suavidade; // 0 = macio (badalo de feltro), 1 = duro
  for (const [t0, f, v] of ev) {
    const i0 = Math.floor(t0 * sr);
    timbre.modos.forEach(([r, a, d], k) => {
      const fr = f * r;
      if (fr > sr * 0.45) return;
      // golpe macio acende pouco os agudos
      const ak = a * v * (k === 0 ? 1 : Math.pow(0.15 + 0.85 * dureza, k * 0.7));
      if (ak < 1e-4) return;
      const tau = d * p.duracao;
      const beat = fr + (0.6 + 1.6 * rand()) * (1 + k * 0.3);
      const ph1 = rand() * 6.283, ph2 = rand() * 6.283;
      const atk = (0.0015 + 0.012 * p.suavidade) * sr; // ataque mais lento = mais suave
      const len = Math.min(N - i0, Math.ceil(tau * 7 * sr));
      const w1 = 2 * Math.PI * fr / sr, w2 = 2 * Math.PI * beat / sr;
      const mb = p.brilho * 0.45;
      const trem = p.tremor;
      for (let j = 0; j < len; j++) {
        const t = j / sr;
        const env = Math.exp(-t / tau) * (j < atk ? j / atk : 1);
        const wob = trem ? 1 + trem * 0.004 * Math.sin(2 * Math.PI * 5.5 * t) * Math.exp(-t / 0.7) : 1;
        out[i0 + j] += ak * env * ((1 - mb) * Math.sin(w1 * j * wob + ph1) + mb * Math.sin(w2 * j * wob + ph2));
      }
    });
    // toque do badalo (só quando duro)
    const nc = Math.floor(0.004 * sr);
    for (let j = 0; j < nc && i0 + j < N; j++) out[i0 + j] += 0.25 * v * dureza * dureza * (rand() * 2 - 1) * Math.exp(-j / (0.0008 * sr));
  }
  // eco: reverb Schroeder simples (4 combs + 2 allpass)
  let y = out;
  if (p.eco > 0) {
    const combs = [1116, 1188, 1277, 1356].map(n => Math.round(n * sr / 44100));
    const wet = new Float32Array(N);
    for (const L of combs) {
      const buf = new Float32Array(L); let idx = 0, lp = 0;
      for (let i = 0; i < N; i++) { const o = buf[idx]; lp = o * 0.7 + lp * 0.3; buf[idx] = out[i] + lp * 0.8; idx = (idx + 1) % L; wet[i] += o * 0.25; }
    }
    for (const L of [556, 441].map(n => Math.round(n * sr / 44100))) {
      const buf = new Float32Array(L); let idx = 0;
      for (let i = 0; i < N; i++) { const b = buf[idx]; const x = wet[i]; const o = -x + b; buf[idx] = x + b * 0.5; idx = (idx + 1) % L; wet[i] = o; }
    }
    y = new Float32Array(N);
    for (let i = 0; i < N; i++) y[i] = out[i] + p.eco * 0.9 * wet[i];
  }
  // fade final e normalização (-1 dBFS)
  const fade = Math.floor(0.12 * sr);
  for (let i = 0; i < fade; i++) y[N - 1 - i] *= Math.pow(i / fade, 2);
  let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(y[i]));
  const g = 0.89 / (pk || 1);
  for (let i = 0; i < N; i++) y[i] *= g;
  return y;
}
if (typeof module !== 'undefined') module.exports = { sintetizar, TIMBRES, MELODIAS, PADRAO };
