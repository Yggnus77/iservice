'use client';

import { useEffect, useRef, useState } from 'react';
import { Camera, ImageUp, Loader2, Trash2 } from 'lucide-react';
import { Avatar, Dialogo, useAviso } from './ui';
import { gravarFoto, prepararFoto, salvarFoto } from '@/lib/foto';

export type PessoaFoto = { id: string; nome: string; foto: string | null };

/** Escolher, ver e salvar a foto de perfil de alguém da equipe (ou a sua). */
export function DialogoFoto({ pessoa, propria, fechar, salvo }: {
  pessoa: PessoaFoto | null; propria: boolean; fechar: () => void; salvo: (url: string | null) => void;
}) {
  const avisar = useAviso();
  const entrada = useRef<HTMLInputElement>(null);
  const [nova, setNova] = useState<{ blob: Blob; previa: string } | null>(null);
  const [erro, setErro] = useState('');
  const [ocupado, setOcupado] = useState<'' | 'preparando' | 'salvando' | 'removendo'>('');
  const [arrastando, setArrastando] = useState(false);

  useEffect(() => {
    if (!pessoa) { setNova(null); setErro(''); setOcupado(''); }
  }, [pessoa]);
  useEffect(() => () => { if (nova) URL.revokeObjectURL(nova.previa); }, [nova]);

  const escolher = async (arquivo?: File | null) => {
    if (!arquivo) return;
    setErro('');
    setOcupado('preparando');
    try {
      const blob = await prepararFoto(arquivo);
      setNova({ blob, previa: URL.createObjectURL(blob) });
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível abrir esta imagem.');
    } finally {
      setOcupado('');
      if (entrada.current) entrada.current.value = '';
    }
  };

  const salvar = async () => {
    if (!pessoa || !nova) return;
    setOcupado('salvando');
    setErro('');
    try {
      const url = await salvarFoto(pessoa.id, nova.blob, propria);
      salvo(url);
      avisar(propria ? 'Sua foto foi atualizada.' : `Foto de ${pessoa.nome} atualizada.`);
      fechar();
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível salvar a foto.');
    } finally {
      setOcupado('');
    }
  };

  const remover = async () => {
    if (!pessoa) return;
    setOcupado('removendo');
    setErro('');
    try {
      await gravarFoto(pessoa.id, null, propria);
      salvo(null);
      avisar(propria ? 'Sua foto foi removida.' : `Foto de ${pessoa.nome} removida.`);
      fechar();
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível remover a foto.');
    } finally {
      setOcupado('');
    }
  };

  const primeiro = pessoa?.nome.trim().split(/\s+/)[0] || '';
  return (
    <Dialogo aberto={!!pessoa} fechar={ocupado ? () => {} : fechar} icone={<Camera />}
      titulo={propria ? 'Sua foto de perfil' : `Foto de perfil de ${primeiro}`}
      texto={propria ? 'Aparece no menu do painel, na aba Equipe e no Registro. É a mesma foto da sua conta iService nos apps.'
        : 'Aparece no menu do painel dessa pessoa, na aba Equipe e no Registro.'}
      rodape={<>
        {pessoa?.foto && !nova ? (
          <button className="botao fantasma" style={{ marginRight: 'auto' }} disabled={!!ocupado} onClick={remover}>
            {ocupado === 'removendo' ? <Loader2 className="girar" /> : <Trash2 />} Remover foto
          </button>
        ) : null}
        <button className="botao contorno" disabled={!!ocupado} onClick={fechar}>Cancelar</button>
        <button className="botao primario" disabled={!nova || !!ocupado} onClick={salvar}>
          {ocupado === 'salvando' ? <Loader2 className="girar" /> : null} Salvar foto
        </button>
      </>}>
      <div
        className={`foto-escolher ${arrastando ? 'arrastando' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setArrastando(true); }}
        onDragLeave={() => setArrastando(false)}
        onDrop={(e) => { e.preventDefault(); setArrastando(false); escolher(e.dataTransfer.files?.[0]); }}
      >
        <div className="foto-previa">
          {nova ? <img src={nova.previa} alt="Nova foto" /> : <Avatar nome={pessoa?.nome} foto={pessoa?.foto} tamanho={132} />}
          {ocupado === 'preparando' ? <span className="foto-carregando"><Loader2 className="girar" /></span> : null}
        </div>
        <div className="foto-acoes">
          <button className="botao contorno" disabled={!!ocupado} onClick={() => entrada.current?.click()}>
            <ImageUp /> {nova || pessoa?.foto ? 'Escolher outra foto' : 'Escolher foto'}
          </button>
          <span className="ajuda">Ou arraste a imagem para cá. JPG, PNG ou WebP. A foto é cortada em quadrado no centro.</span>
        </div>
        <input ref={entrada} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => escolher(e.target.files?.[0])} />
      </div>
      {nova ? <p className="texto-fraco" style={{ margin: '12px 0 0', textAlign: 'center' }}>Gostou? Toque em “Salvar foto”.</p> : null}
      {erro ? <div className="erro-caixa" role="alert" style={{ marginTop: 12 }}>{erro}</div> : null}
    </Dialogo>
  );
}
