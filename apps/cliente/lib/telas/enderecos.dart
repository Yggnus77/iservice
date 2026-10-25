import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Endereços salvos do cliente. O principal é usado nas buscas.
class TelaEnderecos extends ConsumerWidget {
  const TelaEnderecos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider).value;
    final lista = perfil?.enderecos ?? const <Endereco>[];
    final c = context.cores;
    return Scaffold(
      appBar: AppBar(title: const Text('Meus endereços')),
      body: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
        for (final e in lista) ...[
          Card(
            child: ListTile(
              leading: Icon(e.principal ? Symbols.home_rounded : Symbols.location_on_rounded, fill: e.principal ? 1 : 0, color: c.acaoTexto),
              title: Text('${e.rotulo}${e.principal ? ' (principal)' : ''}'),
              subtitle: Text(e.linha1),
              trailing: PopupMenuButton<String>(
                tooltip: 'Opções',
                onSelected: (op) async {
                  try {
                    final conta = ref.read(contaRepo);
                    if (op == 'principal') {
                      await conta.salvarEndereco(
                        id: e.id, logradouro: e.logradouro, lat: e.lat, lng: e.lng, regiaoId: e.regiaoId, bloco: e.bloco, numero: e.numero,
                        complemento: e.complemento, referencia: e.referencia, cep: e.cep, cidade: e.cidade, uf: e.uf, rotulo: e.rotulo, principal: true,
                      );
                    } else {
                      await conta.apagarEndereco(e.id);
                    }
                    ref.invalidate(meuPerfilProvider);
                  } catch (err) {
                    if (context.mounted) mostrarErro(context, err);
                  }
                },
                itemBuilder: (_) => [
                  if (!e.principal) const PopupMenuItem(value: 'principal', child: Text('Usar como principal')),
                  if (lista.length > 1) const PopupMenuItem(value: 'apagar', child: Text('Apagar')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _NovoEndereco())),
          icon: const Icon(Symbols.add_location_alt_rounded),
          label: const Text('Adicionar endereço'),
        ),
      ]),
    );
  }
}

class _NovoEndereco extends ConsumerStatefulWidget {
  const _NovoEndereco();

  @override
  ConsumerState<_NovoEndereco> createState() => _NovoEnderecoState();
}

class _NovoEnderecoState extends ConsumerState<_NovoEndereco> {
  final _form = GlobalKey<FormState>();
  final _rotulo = TextEditingController(text: 'Trabalho');
  final _logradouro = TextEditingController();
  final _bloco = TextEditingController();
  final _complemento = TextEditingController();
  final _referencia = TextEditingController();
  Regiao? _regiao;
  (double, double)? _gps;
  bool _salvando = false;

  Future<void> _salvar() async {
    if (!_form.currentState!.validate() || _regiao == null) {
      if (_regiao == null) mostrarMensagem(context, 'Escolha a cidade ou região.');
      return;
    }
    final ponto = _gps ?? centroDaRegiao(_regiao!.id)!;
    setState(() => _salvando = true);
    try {
      await ref.read(contaRepo).salvarEndereco(
            logradouro: _logradouro.text.trim(),
            lat: ponto.$1,
            lng: ponto.$2,
            regiaoId: _regiao!.id,
            bloco: _bloco.text.trim(),
            complemento: _complemento.text.trim(),
            referencia: _referencia.text.trim(),
            cidade: _regiao!.uf == 'DF' ? 'Brasília' : _regiao!.nome,
            uf: _regiao!.uf,
            rotulo: _rotulo.text.trim().isEmpty ? 'Outro' : _rotulo.text.trim(),
            principal: false,
          );
      ref.invalidate(meuPerfilProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final regioes = ref.watch(regioesProvider).value ?? const <Regiao>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Novo endereço')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(Medidas.margemTela), children: [
          TextFormField(controller: _rotulo, decoration: const InputDecoration(labelText: 'Nome (ex.: Trabalho, Casa da mãe)')),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final r = await escolherEmLista<Regiao>(context, titulo: 'Cidade ou região', opcoes: regioes, rotulo: (r) => r.nomeComUf, atual: _regiao);
              if (r != null) setState(() => _regiao = r);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Cidade ou região administrativa', suffixIcon: Icon(Symbols.expand_more_rounded)),
              isEmpty: _regiao == null,
              child: Text(_regiao?.nomeComUf ?? ''),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(controller: _logradouro, decoration: const InputDecoration(labelText: 'Endereço'), validator: (v) => Validar.obrigatorio(v, 'O endereço')),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextFormField(controller: _bloco, decoration: const InputDecoration(labelText: 'Bloco / casa'))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _complemento, decoration: const InputDecoration(labelText: 'Complemento'))),
          ]),
          const SizedBox(height: 14),
          TextFormField(controller: _referencia, decoration: const InputDecoration(labelText: 'Ponto de referência')),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await lerLocalizacaoAtual();
              if (p == null) {
                if (context.mounted) mostrarMensagem(context, 'Não foi possível ler sua localização.');
                return;
              }
              setState(() {
                _gps = (p.latitude, p.longitude);
                _regiao ??= regioes.where((r) => r.id == regiaoMaisProxima(p.latitude, p.longitude)).firstOrNull;
              });
            },
            icon: Icon(_gps == null ? Symbols.my_location_rounded : Symbols.check_circle_rounded),
            label: Text(_gps == null ? 'Usar minha localização' : 'Localização marcada'),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.all(Medidas.margemTela), child: BotaoPrincipal(rotulo: 'Salvar endereço', carregando: _salvando, aoTocar: _salvar)),
      ),
    );
  }
}
