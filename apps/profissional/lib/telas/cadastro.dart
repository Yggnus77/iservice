import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../estado.dart';

const _total = 6;

/// Cadastro do profissional em 6 passos:
/// 1 dados · 2 endereço e área · 3 e-mail e senha · 4 profissões · 5 documentos · 6 foto e preços.
class TelaCadastro extends ConsumerStatefulWidget {
  const TelaCadastro({super.key, required this.passo});
  final int passo;

  @override
  ConsumerState<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends ConsumerState<TelaCadastro> {
  bool _salvando = false;

  bool get _logado => ref.read(contaRepo).sessao != null;

  Future<void> _ocupado(Future<void> Function() f) async {
    setState(() => _salvando = true);
    try {
      await f();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Depois dos passos 1 e 2: grava (se já tem conta) ou pede e-mail e senha.
  Future<void> _depoisDoEndereco() async {
    if (!_logado) {
      unawaited(context.push('/cadastro/3'));
      return;
    }
    await _ocupado(() async {
      await _gravarRascunhoEArea();
      if (mounted) context.go('/cadastro/4');
    });
  }

  Future<void> _gravarRascunhoEArea() async {
    final pro = ref.read(profissionalRepo);
    if (ref.read(meuPerfilProvider).value?.profissional == null) await pro.ativar();
    final r = ref.read(rascunhoCadastroProvider);
    await ref.read(rascunhoCadastroProvider.notifier).gravar();
    if (r.lat != null) {
      await pro.definirArea(lat: r.lat!, lng: r.lng!, raioKm: ref.read(raioAtendimentoProvider), regiaoId: r.regiaoId);
    }
    ref.invalidate(meuPerfilProvider);
    ref.invalidate(pendenciasProvider);
  }

  Future<void> _enviarParaAnalise() => _ocupado(() async {
        final pend = await ref.read(profissionalRepo).enviarCadastro();
        if (!mounted) return;
        if (pend.isEmpty) {
          ref.invalidate(meuPerfilProvider);
          ref.invalidate(pendenciasProvider);
          context.go('/analise');
        } else {
          mostrarMensagem(context, 'Falta: ${pend.map((p) => nomesPendencias[p] ?? p).join(', ')}.');
          context.go('/cadastro/${passoPendente(pend)}');
        }
      });

  @override
  Widget build(BuildContext context) {
    final tela = switch (widget.passo) {
      1 => PassoDadosPessoais(passo: 1, total: _total, aoContinuar: () => context.push('/cadastro/2')),
      2 => PassoEndereco(
          passo: 2,
          total: _total,
          titulo: 'Onde você mora e atende',
          texto: 'Os clientes não veem seu endereço. Ele serve para calcular a distância.',
          aoContinuar: _depoisDoEndereco,
          extra: const _AreaAtendimento(),
        ),
      3 => PassoConta(
          passo: 3,
          total: _total,
          aoCriar: () => _ocupado(() async {
            await _gravarRascunhoEArea();
            if (context.mounted) context.go('/cadastro/4');
          }),
          aoPrecisarConfirmar: (email) => context.go('/confirmar-email?email=${Uri.encodeComponent(email)}'),
        ),
      4 => _PassoProfissoes(aoContinuar: () => context.push('/cadastro/5')),
      5 => _PassoDocumentos(aoContinuar: () => context.push('/cadastro/6')),
      _ => PassoFoto(
          passo: 6,
          total: _total,
          titulo: 'Foto, sobre você e preços',
          texto: 'A foto precisa ser o mesmo rosto da selfie com o documento.',
          aoContinuar: _enviarParaAnalise,
          extra: const _SobreEPrecos(),
        ),
    };
    return Stack(children: [BannerCadastro(imagem: const AssetImage('assets/cadastro.jpg'), child: tela), if (_salvando) const ColoredBox(color: Color(0x33000000), child: Carregando())]);
  }
}

// ---------------------------------------------------------------------------

class _AreaAtendimento extends ConsumerWidget {
  const _AreaAtendimento();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raio = ref.watch(raioAtendimentoProvider);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Área de atendimento', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Até onde você aceita ir a partir do seu endereço.', style: t.bodySmall),
        Row(children: [
          Expanded(
            child: Slider(
              value: raio,
              min: 3,
              max: 50,
              divisions: 47,
              label: '${raio.round()} km',
              onChanged: (v) => ref.read(raioAtendimentoProvider.notifier).definir(v),
            ),
          ),
          SizedBox(width: 56, child: Text('${raio.round()} km', style: t.titleSmall, textAlign: TextAlign.end)),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _PassoProfissoes extends ConsumerStatefulWidget {
  const _PassoProfissoes({required this.aoContinuar});
  final VoidCallback aoContinuar;

  @override
  ConsumerState<_PassoProfissoes> createState() => _PassoProfissoesState();
}

class _PassoProfissoesState extends ConsumerState<_PassoProfissoes> {
  bool _ocupado = false;

  Future<void> _rodar(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
      ref.invalidate(minhasProfissoesProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _sugerir(Profissao p) async {
    final nome = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Outra especialidade em ${p.nome}'),
        content: TextField(controller: nome, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Ex.: Instalação de interfone')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Adicionar')),
        ],
      ),
    );
    if (ok == true && nome.text.trim().length >= 3) {
      await _rodar(() => ref.read(profissionalRepo).sugerirEspecialidade(p.id, nome.text));
      ref.invalidate(_sugestoesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profissoes = ref.watch(profissoesProvider).value ?? const <Profissao>[];
    final minhas = ref.watch(minhasProfissoesProvider).value;
    final sugestoes = ref.watch(_sugestoesProvider).value ?? const <Especialidade>[];
    final marcadas = minhas?.profissoes.keys.toSet() ?? <String>{};
    final esps = minhas?.especialidades.keys.toSet() ?? <int>{};
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final faltaEsp = marcadas.any((id) {
      final p = profissoes.where((x) => x.id == id).firstOrNull;
      final todas = [...?p?.especialidades, ...sugestoes.where((s) => s.profissaoId == id)];
      return !todas.any((e) => esps.contains(e.id));
    });

    return ModeloPasso(
      cabecalho: const CabecalhoPasso(passo: 4, total: _total, titulo: 'Suas profissões', texto: 'Escolha até 3 e marque as especialidades de cada uma. Elas aparecem no seu perfil.'),
      rotuloBotao: 'Continuar',
      carregando: _ocupado,
      aoContinuar: marcadas.isEmpty || faltaEsp
          ? null
          : widget.aoContinuar,
      rodape: marcadas.isEmpty || faltaEsp
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(marcadas.isEmpty ? 'Escolha pelo menos uma profissão.' : 'Marque ao menos uma especialidade em cada profissão.', style: t.bodySmall),
            )
          : null,
      filhos: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in profissoes)
            FilterChip(
              avatar: Icon(iconeProfissao(p.icone), size: 18),
              label: Text(p.nome),
              selected: marcadas.contains(p.id),
              onSelected: _ocupado
                  ? null
                  : (s) {
                      if (s && marcadas.length >= 3) {
                        mostrarMensagem(context, 'Você pode escolher até 3 profissões.');
                        return;
                      }
                      unawaited(_rodar(() => ref.read(profissionalRepo).marcarProfissao(p.id, s, principal: marcadas.isEmpty)));
                    },
            ),
        ]),
        for (final p in profissoes.where((p) => marcadas.contains(p.id))) ...[
          const SizedBox(height: 24),
          Row(children: [
            BolaProfissao(profissao: p, tamanho: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(p.nome, style: t.titleMedium)),
          ]),
          if (p.documentosExtras.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Para ${p.nome} você também envia ${p.documentosExtras.map((d) => _extras[d]?.$1.toLowerCase() ?? d).join(' e ')} (passo 5).',
                style: t.bodySmall?.copyWith(color: c.alerta),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in [...p.especialidades, ...sugestoes.where((s) => s.profissaoId == p.id)])
              FilterChip(
                label: Text(e.nome),
                selected: esps.contains(e.id),
                onSelected: _ocupado ? null : (s) => _rodar(() => ref.read(profissionalRepo).marcarEspecialidade(e.id, s)),
              ),
            ActionChip(avatar: const Icon(Symbols.add_rounded, size: 18), label: const Text('Outra'), onPressed: () => _sugerir(p)),
          ]),
        ],
      ],
    );
  }
}

final _sugestoesProvider = FutureProvider((ref) => ref.read(profissionalRepo).minhasSugestoes());

// ---------------------------------------------------------------------------

final _documentosProvider = FutureProvider.autoDispose((ref) => ref.read(profissionalRepo).documentos());

/// Documentos que algumas profissões pedem a mais: nome, explicação e ícone.
const _extras = {
  'cnh': ('CNH', 'Carteira de motorista com a categoria do veículo (e EAR, se tiver).', Symbols.id_card_rounded),
  'documento_veiculo': ('Documento do veículo', 'CRLV do veículo que você usa nos fretes.', Symbols.local_shipping_rounded),
  'vinculo_empresa': ('Vínculo com empresa licenciada', 'Carteira, contrato ou declaração da empresa de dedetização licenciada pela Vigilância Sanitária.',
      Symbols.verified_rounded),
};

const _linkPF = 'https://servicos.pf.gov.br/epol-sinic-publico/';
const _linkTJDFT = 'https://www.tjdft.jus.br/servicos/certidoes/certidao-nada-consta';

/// Passo a passo para tirar as certidões (grátis, pela internet).
Future<bool?> _comoTirarCertidao(BuildContext context, {required bool estadual}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        final passos = estadual
            ? const [
                'Abra o site do TJDFT (botão abaixo) e escolha a certidão criminal de 1º grau.',
                'Preencha nome completo, CPF e os dados pedidos. É grátis.',
                'Baixe a certidão e tire um print da tela ou uma foto bem nítida.',
                'Mora fora do DF? Tire a certidão criminal no site do tribunal do seu estado.',
              ]
            : const [
                'Abra o site da Polícia Federal (botão abaixo) e toque em "Emitir certidão".',
                'Preencha nome completo, CPF, data de nascimento e nome da mãe. É grátis.',
                'Baixe a certidão e tire um print da tela ou uma foto bem nítida.',
              ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(estadual ? 'Certidão criminal do TJDFT' : 'Certidão da Polícia Federal', style: t.titleLarge),
            const SizedBox(height: 6),
            Text('Vale a emitida nos últimos 90 dias. Pedimos as duas certidões de todos os profissionais: é o que dá segurança para o cliente receber você em casa.',
                style: t.bodySmall),
            const SizedBox(height: 14),
            for (final (i, passo) in passos.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 12, child: Text('${i + 1}', style: t.labelMedium)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(passo)),
                ]),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(estadual ? _linkTJDFT : _linkPF), mode: LaunchMode.externalApplication),
              icon: const Icon(Symbols.open_in_new_rounded),
              label: Text(estadual ? 'Abrir o site do TJDFT' : 'Abrir o site da Polícia Federal'),
            ),
            const SizedBox(height: 10),
            BotaoPrincipal(rotulo: 'Já tenho, enviar foto', aoTocar: () => Navigator.pop(ctx, true)),
          ]),
        );
      },
    );
final _certificacoesProvider = FutureProvider.autoDispose((ref) => ref.read(profissionalRepo).certificacoes());

/// Documentos e certidões fora do cadastro (Perfil > Documentos): mandar um novo
/// quando vence ou quando a equipe pede.
class TelaDocumentos extends StatelessWidget {
  const TelaDocumentos({super.key});

  @override
  Widget build(BuildContext context) => _PassoDocumentos(aoContinuar: () => context.pop(), avulso: true);
}

class _PassoDocumentos extends ConsumerStatefulWidget {
  const _PassoDocumentos({required this.aoContinuar, this.avulso = false});
  final VoidCallback aoContinuar;

  /// Aberto pelo Perfil, fora do cadastro.
  final bool avulso;

  @override
  ConsumerState<_PassoDocumentos> createState() => _PassoDocumentosState();
}

class _PassoDocumentosState extends ConsumerState<_PassoDocumentos> {
  String? _enviando;

  Future<void> _enviar(String tipo, {bool camera = false}) async {
    if (tipo == 'antecedentes' || tipo == 'antecedentes_estadual') {
      final ok = await _comoTirarCertidao(context, estadual: tipo == 'antecedentes_estadual');
      if (ok != true || !mounted) return;
    }
    final img = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
      preferredCameraDevice: tipo == 'selfie_documento' ? CameraDevice.front : CameraDevice.rear,
    );
    if (img == null) return;
    setState(() => _enviando = tipo);
    try {
      await ref.read(profissionalRepo).enviarDocumento(tipo, await img.readAsBytes());
      ref.invalidate(_documentosProvider);
      ref.invalidate(pendenciasProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = null);
    }
  }

  Future<void> _novaCertificacao(List<CertificacaoSugerida> sugeridas, Set<String> minhasProfissoes) async {
    final nome = TextEditingController();
    final opcoes = sugeridas.where((s) => minhasProfissoes.contains(s.profissaoId) && !s.obrigatoria).toList();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Adicionar certificação', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (opcoes.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [for (final o in opcoes) ActionChip(label: Text(o.nome), onPressed: () => nome.text = o.nome)]),
          const SizedBox(height: 12),
          TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome do curso ou certificado')),
          const SizedBox(height: 12),
          Text('Na próxima tela, escolha a foto do certificado.', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          BotaoPrincipal(rotulo: 'Escolher foto do certificado', aoTocar: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (ok != true || nome.text.trim().isEmpty) return;
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 85);
    setState(() => _enviando = 'cert');
    try {
      await ref.read(profissionalRepo).adicionarCertificacao(
            nome: nome.text.trim(),
            profissaoId: opcoes.where((o) => o.nome == nome.text.trim()).firstOrNull?.profissaoId,
            arquivo: img == null ? null : await img.readAsBytes(),
          );
      ref.invalidate(_certificacoesProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(_documentosProvider).value ?? const <DocumentoEnviado>[];
    final certs = ref.watch(_certificacoesProvider).value ?? const <Map<String, dynamic>>[];
    final sugeridas = ref.watch(certificacoesSugeridasProvider).value ?? const <CertificacaoSugerida>[];
    final minhas = ref.watch(minhasProfissoesProvider).value?.profissoes.keys.toSet() ?? <String>{};
    final profissoes = ref.watch(profissoesProvider).value ?? const <Profissao>[];
    final minhasProfissoes = profissoes.where((p) => minhas.contains(p.id));
    final exigeAntecedentes = minhasProfissoes.isEmpty || minhasProfissoes.any((p) => p.exigeAntecedentes);
    final extras = {for (final p in minhasProfissoes) ...p.documentosExtras}.where(_extras.containsKey).toList()..sort();
    // O último enviado de cada tipo é o que vale.
    DocumentoEnviado? ultimo(String tipo) => docs.where((d) => d.tipo == tipo).lastOrNull;
    bool tem(String tipo) => docs.any((d) => d.tipo == tipo && d.vale);
    final completo = tem('documento_frente') &&
        tem('selfie_documento') &&
        (!exigeAntecedentes || (tem('antecedentes') && tem('antecedentes_estadual'))) &&
        extras.every(tem);
    final t = Theme.of(context).textTheme;
    final c = context.cores;

    String situacao(String tipo, String texto) {
      final d = ultimo(tipo);
      if (d == null) return texto;
      if (d.status == 'recusado') return 'Recusado: ${d.observacao ?? 'envie de novo'}';
      if (d.vencido) return 'Venceu em ${dataCurta(d.validoAte!)}. Toque para enviar um novo.';
      if (d.vencendo) return 'Vence em ${dataCurta(d.validoAte!)}. Já pode enviar um novo.';
      if (d.status == 'aprovado') return d.validoAte == null ? 'Conferido' : 'Conferido · vale até ${dataCurta(d.validoAte!)}';
      return 'Enviado, aguardando conferência';
    }

    final itens = [
      ('documento_frente', 'Documento com foto (frente)', 'RG, CNH ou carteira de trabalho.', Symbols.badge_rounded, false),
      ('documento_verso', 'Documento (verso)', 'Opcional para CNH.', Symbols.flip_rounded, false),
      ('selfie_documento', 'Selfie segurando o documento', 'Rosto e documento visíveis na mesma foto.', Symbols.photo_camera_front_rounded, true),
      if (exigeAntecedentes) ...[
        ('antecedentes', 'Certidão de antecedentes da Polícia Federal', 'Grátis pela internet. Toque para ver o passo a passo.', Symbols.gavel_rounded, false),
        ('antecedentes_estadual', 'Certidão criminal do TJDFT', 'Ou do tribunal do seu estado. Toque para ver o passo a passo.', Symbols.balance_rounded, false),
      ],
      for (final e in extras) (e, _extras[e]!.$1, _extras[e]!.$2, _extras[e]!.$3, false),
    ];

    return ModeloPasso(
      cabecalho: widget.avulso
          ? Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Documentos e certidões', style: t.headlineSmall),
                const SizedBox(height: 6),
                Text('Certidões valem 12 meses e documentos 24 meses. Avisamos 15 dias antes de vencer. Seus documentos não aparecem para os clientes.',
                    style: t.bodyMedium?.copyWith(color: c.textoSuave)),
              ]),
            )
          : const CabecalhoPasso(
              passo: 5,
              total: _total,
              titulo: 'Documentos e certificações',
              texto: 'Conferimos tudo em até 2 dias úteis antes de liberar seu perfil. Seus documentos não aparecem para os clientes.',
            ),
      rotuloBotao: widget.avulso ? 'Pronto' : 'Continuar',
      aoContinuar: (completo || widget.avulso) && _enviando == null ? widget.aoContinuar : null,
      filhos: [
        for (final (tipo, titulo, texto, icone, camera) in itens) ...[
          Card(
            child: ListTile(
              leading: Icon(
                tem(tipo) && !(ultimo(tipo)?.vencendo ?? false) ? Symbols.check_circle_rounded : icone,
                fill: tem(tipo) ? 1 : 0,
                color: !tem(tipo) && ultimo(tipo) != null
                    ? c.perigo
                    : (ultimo(tipo)?.vencendo ?? false)
                        ? c.alerta
                        : tem(tipo)
                            ? c.sucesso
                            : c.acaoTexto,
              ),
              title: Text(titulo, style: t.titleSmall),
              subtitle: Text(situacao(tipo, texto)),
              trailing: _enviando == tipo
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(camera ? Symbols.photo_camera_rounded : Symbols.upload_rounded),
              onTap: _enviando != null ? null : () => _enviar(tipo, camera: camera),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        Text('Certificações (opcional)', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Cursos e certificados aumentam a confiança dos clientes.', style: t.bodySmall),
        const SizedBox(height: 10),
        for (final c in certs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.workspace_premium_rounded),
            title: Text(c['nome'] as String),
            subtitle: Text(c['status'] == 'aprovado' ? 'Conferida' : 'Aguardando conferência'),
            trailing: IconButton(
              tooltip: 'Remover',
              icon: const Icon(Symbols.delete_rounded),
              onPressed: () async {
                await ref.read(profissionalRepo).removerCertificacao(c['id'] as int);
                ref.invalidate(_certificacoesProvider);
              },
            ),
          ),
        OutlinedButton.icon(
          onPressed: _enviando != null ? null : () => _novaCertificacao(sugeridas, minhas),
          icon: const Icon(Symbols.add_rounded),
          label: const Text('Adicionar certificação'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Bio, anos de experiência e o preço de cada especialidade, com a faixa comum da região.
class _SobreEPrecos extends ConsumerStatefulWidget {
  const _SobreEPrecos();

  @override
  ConsumerState<_SobreEPrecos> createState() => _SobreEPrecosState();
}

class _SobreEPrecosState extends ConsumerState<_SobreEPrecos> {
  late final _bio = TextEditingController(text: ref.read(meuPerfilProvider).value?.profissional?.bio);
  late final _anos = TextEditingController(text: ref.read(meuPerfilProvider).value?.profissional?.anosExperiencia?.toString());

  Future<void> _salvarSobre() async {
    try {
      await ref.read(profissionalRepo).salvarSobre(bio: _bio.text.trim(), anosExperiencia: int.tryParse(_anos.text));
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 28),
      Text('Sobre você', style: t.titleMedium),
      const SizedBox(height: 10),
      TextField(
        controller: _bio,
        minLines: 2,
        maxLines: 5,
        maxLength: 400,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Ex.: Eletricista há 12 anos, atendo residências e comércios. Trabalho limpo e com garantia.'),
        onEditingComplete: _salvarSobre,
        onTapOutside: (_) => _salvarSobre(),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: 200,
        child: TextField(
          controller: _anos,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Anos de experiência'),
          onEditingComplete: _salvarSobre,
          onTapOutside: (_) => _salvarSobre(),
        ),
      ),
      const SizedBox(height: 24),
      Text('Seus preços', style: t.titleMedium),
      const SizedBox(height: 4),
      Text('Informe quanto cobra, em média, em cada especialidade e se é por serviço, por hora ou por diária. '
          'Você sempre define o seu valor; a faixa comum na sua região aparece só como referência.',
          style: t.bodySmall),
      const SizedBox(height: 10),
      const EditorPrecos(),
    ]);
  }
}

/// Lista de especialidades marcadas com o preço médio e a forma de cobrança (usada também no Perfil).
/// O preço é obrigatório em cada especialidade: sem ele o cadastro não vai para análise.
class EditorPrecos extends ConsumerWidget {
  const EditorPrecos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minhas = ref.watch(minhasProfissoesProvider).value;
    final profissoes = ref.watch(profissoesProvider).value ?? const <Profissao>[];
    final sugestoes = ref.watch(_sugestoesProvider).value ?? const <Especialidade>[];
    final regiao = ref.watch(meuPerfilProvider).value?.profissional?.regiaoId;
    if (minhas == null) return const Carregando();
    final todas = [for (final p in profissoes) ...p.especialidades, ...sugestoes];
    final marcadas = todas.where((e) => minhas.especialidades.containsKey(e.id)).toList();
    return Column(children: [
      for (final e in marcadas)
        _CampoPreco(
          key: ValueKey(e.id),
          especialidade: e,
          profissao: profissoes.where((p) => p.id == e.profissaoId).firstOrNull?.nome ?? '',
          preco: minhas.especialidades[e.id],
          cobranca: minhas.cobrancas[e.id] ?? Cobranca.servico,
          regiaoId: regiao,
        ),
    ]);
  }
}

class _CampoPreco extends ConsumerStatefulWidget {
  const _CampoPreco(
      {super.key, required this.especialidade, required this.profissao, required this.preco, required this.cobranca, required this.regiaoId});
  final Especialidade especialidade;
  final String profissao;
  final double? preco;
  final Cobranca cobranca;
  final String? regiaoId;

  @override
  ConsumerState<_CampoPreco> createState() => _CampoPrecoState();
}

class _CampoPrecoState extends ConsumerState<_CampoPreco> {
  late final _valor = TextEditingController(text: widget.preco?.toStringAsFixed(0));
  late var _cobranca = widget.cobranca;
  double? get _num => double.tryParse(_valor.text.replaceAll(',', '.'));

  Future<void> _salvar({bool mudouCobranca = false}) async {
    if (!mudouCobranca && _num == widget.preco) return;
    // Abaixo do mínimo da região não salva (o banco também recusa).
    final minimo = ref.read(precoMinimoProvider((widget.especialidade.id, widget.regiaoId, _cobranca))).value;
    if (_num != null && minimo != null && _num! < minimo) return;
    try {
      await ref.read(profissionalRepo).definirPreco(widget.especialidade.id, _num, cobranca: _cobranca);
      ref.invalidate(minhasProfissoesProvider);
      ref.invalidate(pendenciasProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final faixa = ref.watch(faixaPrecoProvider((widget.especialidade.id, widget.regiaoId, _cobranca))).value;
    final minimo = ref.watch(precoMinimoProvider((widget.especialidade.id, widget.regiaoId, _cobranca))).value;
    final abaixoDoMinimo = _num != null && minimo != null && _num! < minimo;
    final aviso = faixa?.aviso(_num);
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.especialidade.nome, style: t.titleSmall),
              Text(widget.profissao, style: t.bodySmall),
              if (faixa != null)
                Text('Comum na região: ${faixaReais(faixa.minimo, faixa.maximo)} ${_cobranca.unidade}', style: t.bodySmall),
              if (minimo != null) Text('Mínimo na sua região: ${reais(minimo)} ${_cobranca.unidade}', style: t.bodySmall),
              if (_num == null)
                Text('Informe quanto você cobra em média', style: t.bodySmall?.copyWith(color: c.alerta))
              else if (abaixoDoMinimo)
                Text('Abaixo do mínimo da plataforma. Informe ${reais(minimo)} ou mais.', style: t.bodySmall?.copyWith(color: c.perigo))
              else if (aviso != null)
                Text(aviso, style: t.bodySmall?.copyWith(color: c.alerta)),
            ]),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,]'))],
              decoration: const InputDecoration(prefixText: r'R$ ', hintText: '0', labelText: 'Média *'),
              onChanged: (_) => setState(() {}),
              onEditingComplete: _salvar,
              onTapOutside: (_) => _salvar(),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final f in Cobranca.values)
            ChoiceChip(
              label: Text(f.rotulo),
              selected: _cobranca == f,
              onSelected: (s) {
                if (!s || f == _cobranca) return;
                setState(() => _cobranca = f);
                unawaited(_salvar(mudouCobranca: true));
              },
            ),
        ]),
      ]),
    );
  }
}
