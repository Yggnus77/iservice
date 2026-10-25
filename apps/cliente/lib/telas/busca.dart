import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

String _normal(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'aaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i < 0 ? ch : para[i]);
  }
  return b.toString();
}

/// Busca por texto: acha profissões e especialidades pelo nome ou por
/// palavras do dia a dia ("chuveiro", "vazamento", "chave do carro").
class TelaBusca extends ConsumerStatefulWidget {
  const TelaBusca({super.key});

  @override
  ConsumerState<TelaBusca> createState() => _TelaBuscaState();
}

class _TelaBuscaState extends ConsumerState<TelaBusca> {
  final _texto = TextEditingController();
  String _termo = '';

  @override
  Widget build(BuildContext context) {
    final profissoes = ref.watch(profissoesProvider).value ?? const <Profissao>[];
    final termo = _normal(_termo.trim());
    final resultados = <(Profissao, Especialidade?)>[];
    if (termo.length >= 2) {
      for (final p in profissoes) {
        final achouProfissao = _normal(p.nome).contains(termo) || p.palavrasChave.any((k) => _normal(k).contains(termo) || termo.contains(_normal(k)));
        if (achouProfissao) resultados.add((p, null));
        for (final e in p.especialidades) {
          if (_normal(e.nome).contains(termo)) resultados.add((p, e));
        }
      }
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _texto,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Ex.: chuveiro, vazamento, faxina', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
          onChanged: (v) => setState(() => _termo = v),
        ),
        actions: [
          if (_termo.isNotEmpty)
            IconButton(tooltip: 'Limpar', icon: const Icon(Symbols.close_rounded), onPressed: () => setState(() {
                  _texto.clear();
                  _termo = '';
                })),
        ],
      ),
      body: termo.length < 2
          ? ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
              Text('Mais buscados', style: t.titleMedium),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in const ['Chuveiro', 'Vazamento', 'Abrir porta', 'Faxina', 'Ar-condicionado', 'Montar móveis', 'Mudança'])
                  ActionChip(label: Text(s), onPressed: () => setState(() {
                        _texto.text = s;
                        _termo = s;
                      })),
              ]),
            ])
          : resultados.isEmpty
              ? const EstadoVazio(icone: Symbols.search_off_rounded, titulo: 'Nada encontrado', texto: 'Tente outra palavra ou veja todas as categorias em Explorar.')
              : ListView.separated(
                  itemCount: resultados.length,
                  separatorBuilder: (_, _) => const Divider(indent: 72),
                  itemBuilder: (_, i) {
                    final (p, e) = resultados[i];
                    return ListTile(
                      leading: BolaProfissao(profissao: p, tamanho: 40),
                      title: Text(e?.nome ?? p.nome),
                      subtitle: Text(e == null ? 'Profissão' : p.nome),
                      trailing: const Icon(Symbols.chevron_right_rounded),
                      onTap: () => context.push('/profissao/${p.id}${e == null ? '' : '?esp=${e.id}'}'),
                    );
                  },
                ),
    );
  }
}
