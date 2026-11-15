import { db, rpc, SUPABASE_URL } from './supabase';

const LADO = 640; // foto final quadrada, 640 x 640
const TIPOS = ['image/jpeg', 'image/png', 'image/webp'];

/** Lê a imagem escolhida, corta no centro em quadrado e reduz para um JPEG leve. */
export async function prepararFoto(arquivo: File): Promise<Blob> {
  if (!TIPOS.includes(arquivo.type)) throw new Error('Use uma foto em JPG, PNG ou WebP.');
  if (arquivo.size > 20 * 1024 * 1024) throw new Error('Esta imagem é grande demais. Escolha uma de até 20 MB.');
  const url = URL.createObjectURL(arquivo);
  try {
    const img = await new Promise<HTMLImageElement>((ok, falha) => {
      const i = new Image();
      i.onload = () => ok(i);
      i.onerror = () => falha(new Error('Não foi possível abrir esta imagem. Tente outra.'));
      i.src = url;
    });
    const menor = Math.min(img.naturalWidth, img.naturalHeight);
    if (menor < 120) throw new Error('A foto é pequena demais. Use uma com pelo menos 120 pixels.');
    const lado = Math.min(LADO, menor);
    const tela = document.createElement('canvas');
    tela.width = lado; tela.height = lado;
    const ctx = tela.getContext('2d');
    if (!ctx) throw new Error('Seu navegador não conseguiu preparar a foto.');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, lado, lado);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, (img.naturalWidth - menor) / 2, (img.naturalHeight - menor) / 2, menor, menor, 0, 0, lado, lado);
    return await new Promise<Blob>((ok, falha) =>
      tela.toBlob((b) => (b ? ok(b) : falha(new Error('Não foi possível preparar a foto.'))), 'image/jpeg', 0.88));
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * Envia a foto para fotos/<id da pessoa>/ e grava no perfil. Cada envio é um arquivo
 * novo (o Storage não deixa sobrescrever o arquivo de outra pessoa).
 * Para a própria foto grava direto no perfil; para a de um colega usa admin_foto_equipe.
 */
export async function salvarFoto(usuarioId: string, foto: Blob, propria: boolean): Promise<string> {
  const caminho = `${usuarioId}/perfil-${Date.now()}.jpg`;
  const { error } = await db().storage.from('fotos').upload(caminho, foto, { contentType: 'image/jpeg', upsert: false, cacheControl: '31536000' });
  if (error) {
    if (/row-level security|unauthorized|403/i.test(error.message)) {
      throw new Error(propria ? 'Sem permissão para enviar a foto. Entre de novo e tente outra vez.'
        : 'Falta aplicar o SQL da foto da equipe no Supabase para trocar a foto de um colega.');
    }
    throw new Error('Não foi possível enviar a foto. Confira a internet e tente de novo.');
  }
  const url = `${SUPABASE_URL}/storage/v1/object/public/fotos/${caminho}`;
  await gravarFoto(usuarioId, url, propria);
  return url;
}

/** Grava (ou tira, com null) a foto no perfil. */
export async function gravarFoto(usuarioId: string, url: string | null, propria: boolean): Promise<void> {
  if (propria) {
    const { error } = await db().from('perfis').update({ foto_url: url }).eq('id', usuarioId);
    if (error) throw new Error('Não foi possível salvar a foto no seu perfil. Tente de novo.');
    return;
  }
  await rpc('admin_foto_equipe', { p_usuario: usuarioId, p_foto: url });
}
