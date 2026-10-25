import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../config.dart';
import '../dados/modelos.dart';
import '../estado/cadastro.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../util/validacao.dart';
import '../widgets/componentes.dart';

/// Cabeçalho dos passos do cadastro: barra de progresso, título e explicação.
class CabecalhoPasso extends StatelessWidget {
  const CabecalhoPasso({super.key, required this.passo, required this.total, required this.titulo, this.texto});
  final int passo;
  final int total;
  final String titulo;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        label: 'Passo $passo de $total',
        child: Row(children: [
          for (var i = 1; i <= total; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i == total ? 0 : 6),
                decoration: BoxDecoration(color: i <= passo ? c.acao : c.linha, borderRadius: BorderRadius.circular(4)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Text('Passo $passo de $total', style: t.labelMedium?.copyWith(color: c.textoSuave)),
      const SizedBox(height: 16),
      Text(titulo, style: t.headlineMedium),
      if (texto != null) ...[const SizedBox(height: 6), Text(texto!, style: t.bodyMedium?.copyWith(color: c.textoSuave))],
      const SizedBox(height: 24),
    ]);
  }
}

/// Estrutura comum dos passos: conteúdo rolável e botão fixo embaixo.
class ModeloPasso extends StatelessWidget {
  const ModeloPasso({super.key, required this.cabecalho, required this.filhos, required this.rotuloBotao, required this.aoContinuar, this.carregando = false, this.rodape});
  final Widget cabecalho;
  final List<Widget> filhos;
  final String rotuloBotao;
  final VoidCallback? aoContinuar;
  final bool carregando;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24),
                children: [cabecalho, ...filhos],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 16),
              child: Column(children: [
                BotaoPrincipal(rotulo: rotuloBotao, aoTocar: aoContinuar, carregando: carregando),
                ?rodape,
              ]),
            ),
          ]),
        ),
      );
}

const _espaco = SizedBox(height: 14);

// ---------------------------------------------------------------------------
// Entrar
// ---------------------------------------------------------------------------

class TelaEntrar extends ConsumerStatefulWidget {
  const TelaEntrar({super.key, required this.aoCriarConta, required this.aoEntrar});
  final VoidCallback aoCriarConta;
  final VoidCallback aoEntrar;

  @override
  ConsumerState<TelaEntrar> createState() => _TelaEntrarState();
}

class _TelaEntrarState extends ConsumerState<TelaEntrar> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _verSenha = false;
  bool _carregando = false;

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await ref.read(contaRepo).entrar(_email.text, _senha.text);
      await ref.read(rascunhoCadastroProvider.notifier).aplicarGuardado();
      if (mounted) widget.aoEntrar();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _esqueci() async {
    if (Validar.email(_email.text) != null) {
      mostrarMensagem(context, 'Digite seu e-mail acima para receber o link.');
      return;
    }
    try {
      await ref.read(contaRepo).recuperarSenha(_email.text);
      if (mounted) mostrarMensagem(context, 'Enviamos um link para ${_email.text.trim()}.');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pro = ref.watch(appProvider) == AppIService.profissional;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela), children: [
            const Align(alignment: Alignment.centerLeft, child: LogoIService(tamanho: 26)),
            const SizedBox(height: 28),
            Text(pro ? 'Entre para receber clientes' : 'Que bom ter você aqui', style: t.headlineMedium),
            const SizedBox(height: 6),
            Text(
              pro ? 'Acesse seu painel, suas solicitações e seus ganhos.' : 'Entre para chamar profissionais verificados perto de você.',
              style: t.bodyMedium?.copyWith(color: context.cores.textoSuave),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Symbols.mail_rounded)),
              validator: Validar.email,
            ),
            _espaco,
            TextFormField(
              controller: _senha,
              obscureText: !_verSenha,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Symbols.lock_rounded),
                suffixIcon: IconButton(
                  tooltip: _verSenha ? 'Esconder senha' : 'Mostrar senha',
                  icon: Icon(_verSenha ? Symbols.visibility_off_rounded : Symbols.visibility_rounded),
                  onPressed: () => setState(() => _verSenha = !_verSenha),
                ),
              ),
              validator: (v) => (v ?? '').isEmpty ? 'Digite sua senha.' : null,
              onFieldSubmitted: (_) => _entrar(),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _esqueci, child: const Text('Esqueci minha senha'))),
            const SizedBox(height: 12),
            BotaoPrincipal(rotulo: 'Entrar', aoTocar: _entrar, carregando: _carregando),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: widget.aoCriarConta, child: Text(pro ? 'Quero ser profissional iService' : 'Criar conta')),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo: dados pessoais
// ---------------------------------------------------------------------------

class PassoDadosPessoais extends ConsumerStatefulWidget {
  const PassoDadosPessoais({super.key, required this.passo, required this.total, required this.aoContinuar});
  final int passo;
  final int total;
  final VoidCallback aoContinuar;

  @override
  ConsumerState<PassoDadosPessoais> createState() => _PassoDadosPessoaisState();
}

class _PassoDadosPessoaisState extends ConsumerState<PassoDadosPessoais> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: ref.read(rascunhoCadastroProvider).nome);
  late final _nasc = TextEditingController(
    text: ref.read(rascunhoCadastroProvider).nascimento == null ? '' : dataCurta(ref.read(rascunhoCadastroProvider).nascimento!),
  );
  late final _cpf = TextEditingController(text: cpfFormatado(ref.read(rascunhoCadastroProvider).cpf));
  late final _tel = TextEditingController(text: telefoneFormatado(ref.read(rascunhoCadastroProvider).telefone));
  final _mCpf = mascaraCpf(), _mTel = mascaraTelefone(), _mData = mascaraData();

  void _continuar() {
    if (!_form.currentState!.validate()) return;
    final n = ref.read(rascunhoCadastroProvider.notifier);
    n.atualizar(ref.read(rascunhoCadastroProvider).copiar(
          nome: _nome.text.trim(),
          nascimento: lerData(_nasc.text),
          cpf: soDigitos(_cpf.text),
          telefone: soDigitos(_tel.text),
        ));
    widget.aoContinuar();
  }

  @override
  Widget build(BuildContext context) {
    final pro = ref.watch(appProvider) == AppIService.profissional;
    return Form(
      key: _form,
      child: ModeloPasso(
        cabecalho: CabecalhoPasso(
          passo: widget.passo,
          total: widget.total,
          titulo: 'Seus dados pessoais',
          texto: pro ? 'Usamos para verificar sua identidade. Os clientes veem só seu nome e sua foto.' : 'Precisamos deles para sua segurança e a do profissional.',
        ),
        rotuloBotao: 'Continuar',
        aoContinuar: _continuar,
        filhos: [
          TextFormField(
            controller: _nome,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Nome completo'),
            validator: Validar.nomeCompleto,
          ),
          _espaco,
          TextFormField(
            controller: _nasc,
            keyboardType: TextInputType.number,
            inputFormatters: [_mData],
            decoration: const InputDecoration(labelText: 'Data de nascimento', hintText: 'dd/mm/aaaa'),
            validator: Validar.nascimento,
          ),
          _espaco,
          TextFormField(
            controller: _cpf,
            keyboardType: TextInputType.number,
            inputFormatters: [_mCpf],
            decoration: const InputDecoration(labelText: 'CPF'),
            validator: Validar.cpf,
          ),
          _espaco,
          TextFormField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            inputFormatters: [_mTel],
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(labelText: 'Celular com WhatsApp'),
            validator: Validar.telefone,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo: endereço
// ---------------------------------------------------------------------------

class PassoEndereco extends ConsumerStatefulWidget {
  const PassoEndereco({super.key, required this.passo, required this.total, required this.aoContinuar, this.titulo, this.texto, this.extra});
  final int passo;
  final int total;
  final VoidCallback aoContinuar;
  final String? titulo;
  final String? texto;

  /// Conteúdo a mais no fim (o app Profissional põe a área de atendimento).
  final Widget? extra;

  @override
  ConsumerState<PassoEndereco> createState() => _PassoEnderecoState();
}

class _PassoEnderecoState extends ConsumerState<PassoEndereco> {
  final _form = GlobalKey<FormState>();
  late final RascunhoCadastro _r = ref.read(rascunhoCadastroProvider);
  late final _logradouro = TextEditingController(text: _r.logradouro);
  late final _bloco = TextEditingController(text: _r.bloco);
  late final _complemento = TextEditingController(text: _r.complemento);
  late final _referencia = TextEditingController(text: _r.referencia);
  late final _cep = TextEditingController(text: _r.cep);
  late String? _regiaoId = _r.regiaoId;
  late double? _lat = _r.lat, _lng = _r.lng;
  bool _gps = false;
  bool _lendoGps = false;

  Future<void> _usarGps() async {
    setState(() => _lendoGps = true);
    try {
      final p = await lerLocalizacaoAtual();
      if (p == null) {
        if (mounted) mostrarMensagem(context, 'Não foi possível ler sua localização. Escolha a região na lista.');
        return;
      }
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _gps = true;
      });
      // Sem região escolhida, sugere a do centro mais perto (o usuário pode trocar).
      _regiaoId ??= regiaoMaisProxima(p.latitude, p.longitude);
    } finally {
      if (mounted) setState(() => _lendoGps = false);
    }
  }

  void _continuar() {
    if (!_form.currentState!.validate()) return;
    if (_regiaoId == null) {
      mostrarMensagem(context, 'Escolha a cidade ou região administrativa.');
      return;
    }
    final reg = (ref.read(regioesProvider).value ?? const <Regiao>[]).firstWhere((r) => r.id == _regiaoId);
    final centro = _centros[_regiaoId];
    ref.read(rascunhoCadastroProvider.notifier).atualizar(_r.copiar(
          regiaoId: _regiaoId,
          cidade: reg.uf == 'DF' ? 'Brasília' : reg.nome,
          uf: reg.uf,
          logradouro: _logradouro.text.trim(),
          bloco: _bloco.text.trim(),
          complemento: _complemento.text.trim(),
          referencia: _referencia.text.trim(),
          cep: soDigitos(_cep.text),
          lat: _gps ? _lat : (_lat ?? centro?.$1),
          lng: _gps ? _lng : (_lng ?? centro?.$2),
        ));
    widget.aoContinuar();
  }

  @override
  Widget build(BuildContext context) {
    final regioes = ref.watch(regioesProvider).value ?? const <Regiao>[];
    final reg = regioes.where((r) => r.id == _regiaoId).firstOrNull;
    final c = context.cores;
    return Form(
      key: _form,
      child: ModeloPasso(
        cabecalho: CabecalhoPasso(
          passo: widget.passo,
          total: widget.total,
          titulo: widget.titulo ?? 'Seu endereço',
          texto: widget.texto ?? 'É onde os profissionais vão atender. Você pode salvar outros depois.',
        ),
        rotuloBotao: 'Continuar',
        aoContinuar: _continuar,
        filhos: [
          InkWell(
            borderRadius: BorderRadius.circular(Medidas.raioControle),
            onTap: () async {
              final r = await escolherEmLista<Regiao>(context, titulo: 'Cidade ou região', opcoes: regioes, rotulo: (r) => r.nomeComUf, atual: reg);
              if (r != null) setState(() => _regiaoId = r.id);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Cidade ou região administrativa', suffixIcon: Icon(Symbols.expand_more_rounded)),
              isEmpty: reg == null,
              child: Text(reg?.nomeComUf ?? ''),
            ),
          ),
          _espaco,
          TextFormField(
            controller: _logradouro,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Endereço', hintText: 'Ex.: SQS 308, QNL 12 Conj. B, Rua 10 Qd 5'),
            validator: (v) => Validar.obrigatorio(v, 'O endereço'),
          ),
          _espaco,
          Row(children: [
            Expanded(child: TextFormField(controller: _bloco, decoration: const InputDecoration(labelText: 'Bloco / casa / lote'))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _complemento, decoration: const InputDecoration(labelText: 'Apto / complemento'))),
          ]),
          _espaco,
          TextFormField(controller: _referencia, decoration: const InputDecoration(labelText: 'Ponto de referência (opcional)')),
          _espaco,
          TextFormField(
            controller: _cep,
            keyboardType: TextInputType.number,
            inputFormatters: [mascaraCep()],
            decoration: const InputDecoration(labelText: 'CEP (opcional)'),
            validator: Validar.cep,
          ),
          const SizedBox(height: 16),
          Card(
            color: _gps ? c.sucessoSuave : c.superficieSuave,
            child: ListTile(
              leading: Icon(_gps ? Symbols.check_circle_rounded : Symbols.my_location_rounded, color: _gps ? c.sucesso : c.acaoTexto),
              title: Text(_gps ? 'Localização marcada' : 'Usar minha localização'),
              subtitle: Text(_gps ? 'A distância até os profissionais fica mais precisa.' : 'Recomendado se você está no endereço agora.'),
              trailing: _lendoGps ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: _lendoGps ? null : _usarGps,
            ),
          ),
          ?widget.extra,
        ],
      ),
    );
  }
}

/// Centros aproximados das regiões, usados quando o usuário não marca o GPS.
/// (os mesmos do catálogo do banco)
const _centros = <String, (double, double)>{
  'asa-sul': (-15.8150, -47.8960), 'asa-norte': (-15.7630, -47.8820), 'sudoeste': (-15.7990, -47.9250),
  'noroeste': (-15.7400, -47.9100), 'lago-sul': (-15.8400, -47.8500), 'lago-norte': (-15.7300, -47.8400),
  'park-way': (-15.8950, -47.9600), 'cruzeiro': (-15.7900, -47.9400), 'guara': (-15.8300, -47.9800),
  'aguas-claras': (-15.8400, -48.0270), 'vicente-pires': (-15.8030, -48.0300), 'jardim-botanico': (-15.8700, -47.8000),
  'taguatinga': (-15.8330, -48.0560), 'nucleo-bandeirante': (-15.8710, -47.9670), 'riacho-fundo': (-15.8830, -48.0170),
  'sobradinho': (-15.6530, -47.7900), 'paranoa': (-15.7760, -47.7800), 'ceilandia': (-15.8190, -48.1080),
  'samambaia': (-15.8780, -48.0850), 'gama': (-16.0190, -48.0620), 'santa-maria': (-16.0170, -48.0130),
  'recanto-das-emas': (-15.9080, -48.0620), 'planaltina': (-15.6200, -47.6500), 'sao-sebastiao': (-15.9030, -47.7740),
  'brazlandia': (-15.6700, -48.2000), 'valparaiso': (-16.0650, -47.9750), 'aguas-lindas': (-15.7610, -48.2810),
  'luziania': (-16.2530, -47.9500), 'novo-gama': (-16.0590, -48.0410), 'cidade-ocidental': (-16.0780, -47.9250),
  'santo-antonio': (-15.9410, -48.2570), 'planaltina-go': (-15.4520, -47.6140), 'formosa': (-15.5370, -47.3340),
};

(double, double)? centroDaRegiao(String? id) => _centros[id];

String regiaoMaisProxima(double lat, double lng) {
  String? melhor;
  var menor = double.infinity;
  _centros.forEach((id, c) {
    final d = (c.$1 - lat) * (c.$1 - lat) + (c.$2 - lng) * (c.$2 - lng);
    if (d < menor) {
      menor = d;
      melhor = id;
    }
  });
  return melhor!;
}

// ---------------------------------------------------------------------------
// Passo: e-mail e senha (cria a conta)
// ---------------------------------------------------------------------------

class PassoConta extends ConsumerStatefulWidget {
  const PassoConta({super.key, required this.passo, required this.total, required this.aoCriar, required this.aoPrecisarConfirmar});
  final int passo;
  final int total;
  final VoidCallback aoCriar;

  /// O Supabase exige confirmar o e-mail antes do primeiro login.
  final ValueChanged<String> aoPrecisarConfirmar;

  @override
  ConsumerState<PassoConta> createState() => _PassoContaState();
}

class _PassoContaState extends ConsumerState<PassoConta> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _senha2 = TextEditingController();
  late final _indicacao = TextEditingController(text: ref.read(rascunhoCadastroProvider).indicacao);
  bool _aceite = false;
  bool _carregando = false;

  Future<void> _criar() async {
    if (!_form.currentState!.validate()) return;
    if (!_aceite) {
      mostrarMensagem(context, 'Para continuar, aceite os Termos de Uso e a Política de Privacidade.');
      return;
    }
    setState(() => _carregando = true);
    final n = ref.read(rascunhoCadastroProvider.notifier);
    n.atualizar(ref.read(rascunhoCadastroProvider).copiar(indicacao: _indicacao.text.trim()));
    try {
      final logado = await n.criarConta(email: _email.text, senha: _senha.text, app: ref.read(appProvider));
      if (!mounted) return;
      logado ? widget.aoCriar() : widget.aoPrecisarConfirmar(_email.text.trim());
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ModeloPasso(
        cabecalho: CabecalhoPasso(passo: widget.passo, total: widget.total, titulo: 'E-mail e senha', texto: 'É com eles que você entra no app.'),
        rotuloBotao: 'Criar conta',
        aoContinuar: _criar,
        carregando: _carregando,
        filhos: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: Validar.email,
          ),
          _espaco,
          TextFormField(
            controller: _senha,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'Senha', helperText: 'Mínimo de 8 caracteres, com letras e números.'),
            validator: Validar.senha,
          ),
          _espaco,
          TextFormField(
            controller: _senha2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repita a senha'),
            validator: (v) => v == _senha.text ? null : 'As senhas não são iguais.',
          ),
          _espaco,
          TextFormField(
            controller: _indicacao,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código de indicação (opcional)'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _aceite,
            onChanged: (v) => setState(() => _aceite = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Li e aceito os Termos de Uso e a Política de Privacidade.', style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Aviso de "confirme seu e-mail".
class TelaConfirmarEmail extends StatelessWidget {
  const TelaConfirmarEmail({super.key, required this.email, required this.aoIrParaEntrar});
  final String email;
  final VoidCallback aoIrParaEntrar;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: EstadoVazio(
            icone: Symbols.mark_email_unread_rounded,
            titulo: 'Confirme seu e-mail',
            texto: 'Enviamos um link para $email. Toque nele e depois entre no app: seus dados já estão guardados.',
            acao: 'Já confirmei, entrar',
            aoTocarAcao: aoIrParaEntrar,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Passo: foto de perfil (obrigatória nos dois apps)
// ---------------------------------------------------------------------------

class PassoFoto extends ConsumerStatefulWidget {
  const PassoFoto({super.key, required this.passo, required this.total, required this.aoContinuar, this.titulo, this.texto, this.extra});
  final int passo;
  final int total;
  final VoidCallback aoContinuar;
  final String? titulo;
  final String? texto;
  final Widget? extra;

  @override
  ConsumerState<PassoFoto> createState() => _PassoFotoState();
}

class _PassoFotoState extends ConsumerState<PassoFoto> {
  bool _enviando = false;

  Future<void> _escolher(ImageSource fonte) async {
    final img = await ImagePicker().pickImage(source: fonte, maxWidth: 1080, maxHeight: 1080, imageQuality: 85, preferredCameraDevice: CameraDevice.front);
    if (img == null) return;
    setState(() => _enviando = true);
    try {
      final arquivos = ref.read(arquivosRepo);
      final caminho = await arquivos.enviar(bucket: 'fotos', nome: 'perfil-${DateTime.now().millisecondsSinceEpoch}.jpg', bytes: await img.readAsBytes());
      await ref.read(contaRepo).salvarFoto(arquivos.urlPublica('fotos', caminho));
      ref.invalidate(meuPerfilProvider);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(meuPerfilProvider).value;
    final temFoto = (perfil?.fotoUrl ?? '').isNotEmpty;
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return ModeloPasso(
      cabecalho: CabecalhoPasso(
        passo: widget.passo,
        total: widget.total,
        titulo: widget.titulo ?? 'Sua foto de perfil',
        texto: widget.texto ?? 'O profissional vê sua foto quando recebe o pedido. Isso dá segurança aos dois lados.',
      ),
      rotuloBotao: 'Continuar',
      aoContinuar: temFoto && !_enviando ? widget.aoContinuar : null,
      filhos: [
        Center(
          child: Stack(alignment: Alignment.center, children: [
            Avatar(nome: perfil?.nome ?? '', url: perfil?.fotoUrl, tamanho: 152),
            if (_enviando) const SizedBox.square(dimension: 152, child: CircularProgressIndicator(strokeWidth: 3)),
          ]),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _enviando ? null : () => _escolher(ImageSource.camera),
              icon: const Icon(Symbols.photo_camera_rounded),
              label: const Text('Tirar foto'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _enviando ? null : () => _escolher(ImageSource.gallery),
              icon: const Icon(Symbols.photo_library_rounded),
              label: const Text('Galeria'),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Card(
          color: c.superficieSuave,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dicas para uma boa foto', style: t.titleSmall),
              const SizedBox(height: 8),
              for (final d in const ['Rosto de frente e bem iluminado', 'Sem óculos escuros, boné ou filtros', 'Só você na foto'])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [Icon(Symbols.check_rounded, size: 18, color: c.sucesso), const SizedBox(width: 8), Expanded(child: Text(d, style: t.bodySmall))]),
                ),
            ]),
          ),
        ),
        if (!temFoto) ...[
          const SizedBox(height: 12),
          Text('A foto é obrigatória para usar o iService.', style: t.bodySmall, textAlign: TextAlign.center),
        ],
        ?widget.extra,
      ],
    );
  }
}
