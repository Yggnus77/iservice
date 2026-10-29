'use client';

import { useEffect, useRef } from 'react';
import type { Map as MapaLeaflet, Layer } from 'leaflet';

export type Ponto = { lat: number; lng: number; peso: number; total: number; sem: number };

// Centro do DF; o mapa cobre Brasília e o Entorno.
const CENTRO: [number, number] = [-15.83, -47.95];

export default function MapaCalor({ pontos }: { pontos: Ponto[] }) {
  const elemento = useRef<HTMLDivElement>(null);
  const mapa = useRef<MapaLeaflet | null>(null);
  const camadas = useRef<Layer[]>([]);

  useEffect(() => {
    let vivo = true;
    (async () => {
      const L = (await import('leaflet')).default;
      (window as unknown as { L: typeof L }).L = L;
      await import('leaflet.heat');
      if (!vivo || !elemento.current) return;
      if (!mapa.current) {
        mapa.current = L.map(elemento.current, { zoomControl: true, scrollWheelZoom: true }).setView(CENTRO, 10);
        L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
          attribution: '&copy; OpenStreetMap &copy; CARTO', subdomains: 'abcd', maxZoom: 18,
        }).addTo(mapa.current);
      }
      camadas.current.forEach((c) => c.remove());
      camadas.current = [];
      if (!pontos.length) return;
      const max = Math.max(...pontos.map((p) => p.peso));
      const heat = (L as unknown as { heatLayer: (p: [number, number, number][], o: object) => Layer }).heatLayer(
        pontos.map((p) => [p.lat, p.lng, p.peso / max]),
        { radius: 28, blur: 22, maxZoom: 13, minOpacity: 0.35, gradient: { 0.2: '#ffe2bd', 0.45: '#ffb35c', 0.7: '#ff8a00', 0.9: '#c25400', 1: '#7a2e00' } },
      );
      heat.addTo(mapa.current);
      camadas.current.push(heat);
      // Pontos invisíveis maiores que a mancha, só para mostrar os números ao passar o mouse.
      for (const p of pontos) {
        const alvo = L.circleMarker([p.lat, p.lng], { radius: 14, opacity: 0, fillOpacity: 0 })
          .bindTooltip(`<strong>${p.total} ${p.total === 1 ? 'busca' : 'buscas'}</strong><br>${p.sem} sem resultado`, { direction: 'top' });
        alvo.addTo(mapa.current);
        camadas.current.push(alvo);
      }
    })();
    return () => { vivo = false; };
  }, [pontos]);

  useEffect(() => () => { mapa.current?.remove(); mapa.current = null; }, []);

  return <div ref={elemento} className="mapa" role="img" aria-label="Mapa de calor das buscas" />;
}
