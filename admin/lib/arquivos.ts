import { db, SUPABASE_URL } from './supabase';

const publicos = new Set(['fotos', 'portfolio', 'avaliacoes']);
const cache = new Map<string, { url: string; ate: number }>();

/** Endereço para mostrar um arquivo do Storage. Privados (documentos, pedidos) ganham link temporário. */
export async function urlArquivo(bucket: string, caminho?: string | null): Promise<string | null> {
  if (!caminho) return null;
  if (/^https?:\/\//.test(caminho)) return caminho;
  // Alguns caminhos chegam com o nome do bucket na frente.
  const limpo = caminho.startsWith(bucket + '/') ? caminho.slice(bucket.length + 1) : caminho;
  if (publicos.has(bucket)) return `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${limpo}`;
  const chave = bucket + '/' + limpo;
  const c = cache.get(chave);
  if (c && c.ate > Date.now()) return c.url;
  const { data, error } = await db().storage.from(bucket).createSignedUrl(limpo, 3600);
  if (error || !data) return null;
  cache.set(chave, { url: data.signedUrl, ate: Date.now() + 50 * 60 * 1000 });
  return data.signedUrl;
}

/** Foto de perfil: o banco guarda a URL pública inteira ou "fotos/<id>/<arquivo>". */
export function urlFoto(foto?: string | null): string | null {
  if (!foto) return null;
  if (/^https?:\/\//.test(foto)) return foto;
  return `${SUPABASE_URL}/storage/v1/object/public/${foto.replace(/^\/+/, '')}`;
}

export function ePdf(caminho?: string | null): boolean {
  return !!caminho && /\.pdf($|\?)/i.test(caminho);
}
