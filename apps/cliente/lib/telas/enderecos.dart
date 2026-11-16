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
                        complemento: e.complemento, bairro: e.bairro, referencia: e.referencia, cep: e.cep, cidade: e.cidade, uf: e.uf, rotulo: e.rotulo,
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
  final _bairro = TextEditingController();
  final _cep = TextEditingController();
  final _referencia = TextEditingController();
  Regiao? _regiao;
  (double, double)? _gps;
  bool _salvando = false;

  Future<void> _salvar() async {
    if (_regiao == null) {
      mostrarMensagem(context, 'Escolha a cidade ou região.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    final regiao = _regiao!;
    setState(() => _salvando = true);
    try {
      final ponto = await localizarEConfirmar(
        context,
        regiao: regiao,
        centro: centroDaRegiao(regiao.id),
        logradouro: _logradouro.text,
        bloco: _bloco.text,
        bairro: _bairro.text,
        gps: _gps,
      );
      if (ponto == null) return;
      await ref.read(contaRepo).salvarEndereco(
            logradouro: _logradouro.text.trim(),
            lat: ponto.latitude,
            lng: ponto.longitude,
            regiaoId: regiao.id,
            bloco: _bloco.text.trim(),
            complemento: _complemento.text.trim(),
            bairro: _bairro.text.trim(),
            referencia: _referencia.text.trim(),
            cep: soDigitos(_cep.text),
            cidade: regiao.uf == 'DF' ? 'Brasília' : regiao.nome,
            uf: regiao.uf,
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
          CampoRegiao(regioes: regioes, atual: _regiao, aoEscolher: (r) => setState(() => _regiao = r)),
          const SizedBox(height: 14),
          ...camposEndereco(
            uf: _regiao?.uf,
            logradouro: _logradouro,
            bloco: _bloco,
            complemento: _complemento,
            bairro: _bairro,
            cep: _cep,
            referencia: _referencia,
          ),
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
