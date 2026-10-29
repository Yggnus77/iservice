import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../dados/modelos.dart';
import '../dados/repositorios.dart';
import '../telas/confirmar_celular.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../util/icones.dart';

/// Logo em texto: "iServi" azul e "ce" laranja, com o pin.
class LogoIService extends StatelessWidget {
  const LogoIService({super.key, this.tamanho = 28, this.claro = false});
  final double tamanho;

  /// Versão para fundo escuro.
  final bool claro;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily, fontSize: tamanho, fontWeight: FontWeight.w800, letterSpacing: -.5);
    return Semantics(
      label: 'iService',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.location_on_rounded, fill: 1, size: tamanho * 1.15, color: claro ? Colors.white : Cores.azul),
          const SizedBox(width: 2),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'iServi', style: estilo.copyWith(color: claro ? Colors.white : Cores.azul)),
            TextSpan(text: 'ce', style: estilo.copyWith(color: Cores.laranja)),
          ])),
        ]),
      ),
    );
  }
}

/// Foto redonda. Sem foto, mostra as iniciais.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.nome, this.url, this.tamanho = 48, this.online = false});
  final String nome;
  final String? url;
  final double tamanho;

  /// Bolinha verde de "disponível agora".
  final bool online;

  String get _iniciais {
    final p = nome.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final semFoto = Container(
      alignment: Alignment.center,
      color: c.acaoSuave,
      child: Text(_iniciais, style: TextStyle(fontSize: tamanho * .36, fontWeight: FontWeight.w700, color: c.acaoTexto)),
    );
    return SizedBox.square(
      dimension: tamanho,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipOval(
          child: SizedBox.square(
            dimension: tamanho,
            child: url == null || url!.isEmpty
                ? semFoto
                : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, placeholder: (_, _) => semFoto, errorWidget: (_, _, _) => semFoto),
          ),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: tamanho * .28,
              height: tamanho * .28,
              decoration: BoxDecoration(
                color: Cores.verde,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// ★ 4,9 (248)
class NotaCompacta extends StatelessWidget {
  const NotaCompacta({super.key, required this.nota, this.total, this.tamanho = 14});
  final double nota;
  final int? total;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: 'Nota ${nota.toStringAsFixed(1)} de 5${total == null ? '' : ', $total avaliações'}',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.star_rounded, fill: 1, size: tamanho + 2, color: Cores.estrela),
          const SizedBox(width: 3),
          Text(nota == 0 ? 'Novo' : formatarNota(nota), style: t.labelMedium?.copyWith(fontSize: tamanho)),
          if (total != null && nota > 0) Text(' ($total)', style: t.bodySmall?.copyWith(fontSize: tamanho - 1)),
        ]),
      ),
    );
  }
}

String formatarNota(double n) => nota(n);

/// Cinco estrelas para mostrar ou escolher a nota.
class Estrelas extends StatelessWidget {
  const Estrelas({super.key, required this.valor, this.aoEscolher, this.tamanho = 22});
  final double valor;
  final ValueChanged<int>? aoEscolher;
  final double tamanho;

  static const _rotulos = ['Péssimo', 'Ruim', 'Regular', 'Bom', 'Excelente'];

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        aoEscolher == null
            ? Icon(Symbols.star_rounded, fill: i <= valor.round() ? 1 : 0, size: tamanho, color: Cores.estrela)
            : Semantics(
                button: true,
                selected: i == valor.round(),
                label: '$i estrela${i > 1 ? 's' : ''}: ${_rotulos[i - 1]}',
                child: InkResponse(
                  onTap: () => aoEscolher!(i),
                  radius: tamanho,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Symbols.star_rounded, fill: i <= valor.round() ? 1 : 0, size: tamanho, color: Cores.estrela),
                  ),
                ),
              ),
    ]);
  }
}

/// Bola colorida com o ícone da profissão (como no protótipo).
class BolaProfissao extends StatelessWidget {
  const BolaProfissao({super.key, required this.profissao, this.tamanho = 56});
  final Profissao profissao;
  final double tamanho;

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [corHex(profissao.corInicio), corHex(profissao.corFim)],
          ),
          boxShadow: [BoxShadow(color: corHex(profissao.corFim).withValues(alpha: .28), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(iconeProfissao(profissao.icone), color: Colors.white, size: tamanho * .5, fill: 1),
      );
}

/// Botão da grade de categorias.
class BotaoCategoria extends StatelessWidget {
  const BotaoCategoria({super.key, required this.profissao, required this.aoTocar, this.legenda});
  final Profissao profissao;
  final VoidCallback aoTocar;
  final String? legenda;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: profissao.nome,
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BolaProfissao(profissao: profissao),
            const SizedBox(height: 8),
            Text(profissao.nome, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(height: 1.2)),
            if (legenda != null) Text(legenda!, style: t.bodySmall?.copyWith(fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class Selo extends StatelessWidget {
  const Selo({super.key, required this.texto, this.icone, required this.cor, required this.fundo});
  final String texto;
  final IconData? icone;
  final Color cor;
  final Color fundo;

  factory Selo.verificado(BuildContext context) =>
      Selo(texto: 'Verificado', icone: Symbols.verified_rounded, cor: context.cores.sucesso, fundo: context.cores.sucessoSuave);

  factory Selo.novo(BuildContext context) =>
      Selo(texto: 'Novo', icone: Symbols.auto_awesome_rounded, cor: context.cores.alerta, fundo: context.cores.alertaSuave);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(Medidas.raioPilula)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icone != null) ...[Icon(icone, size: 14, color: cor, fill: 1), const SizedBox(width: 4)],
          Text(texto, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor)),
        ]),
      );
}

/// Cartão de profissional usado na busca, no ranking e nos favoritos.
class CartaoProfissional extends StatelessWidget {
  const CartaoProfissional({super.key, required this.p, required this.aoTocar, this.profissaoNome, this.mostrarPosicao = false});
  final ProfissionalResumo p;
  final VoidCallback aoTocar;
  final String? profissaoNome;
  final bool mostrarPosicao;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Card(
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(nome: p.nome, url: p.fotoUrl, tamanho: 60, online: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(p.nome, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (p.verificado) ...[const SizedBox(width: 4), Icon(Symbols.verified_rounded, size: 16, fill: 1, color: c.acaoTexto)],
                ]),
                if (profissaoNome != null) Text(profissaoNome!, style: t.bodySmall),
                const SizedBox(height: 4),
                Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (p.novo) Selo.novo(context) else NotaCompacta(nota: p.notaMedia, total: p.totalAvaliacoes),
                  if (p.distanciaKm > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Symbols.location_on_rounded, size: 14, color: c.textoSuave),
                      Text(distancia(p.distanciaKm), style: t.bodySmall),
                    ]),
                  if (p.servicosConcluidos > 0) Text('${p.servicosConcluidos} serviços', style: t.bodySmall),
                ]),
                if (p.especialidades.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(p.especialidades.take(3).join(' · '), style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            if (p.precoAPartir != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('a partir de', style: t.bodySmall?.copyWith(fontSize: 11)),
                Text(reais(p.precoAPartir), style: t.titleSmall?.copyWith(color: c.acaoTexto)),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Botão principal que mostra carregando enquanto a ação roda.
class BotaoPrincipal extends StatelessWidget {
  const BotaoPrincipal({super.key, required this.rotulo, required this.aoTocar, this.carregando = false, this.icone});
  final String rotulo;
  final VoidCallback? aoTocar;
  final bool carregando;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return FilledButton(
      onPressed: carregando ? null : aoTocar,
      child: carregando
          ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.textoSuave))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (icone != null) ...[Icon(icone, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(rotulo, overflow: TextOverflow.ellipsis)),
            ]),
    );
  }
}

class EstadoVazio extends StatelessWidget {
  const EstadoVazio({super.key, required this.icone, required this.titulo, this.texto, this.acao, this.aoTocarAcao, this.rodape});
  final IconData icone;
  final Widget? rodape;
  final String titulo;
  final String? texto;
  final String? acao;
  final VoidCallback? aoTocarAcao;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: c.acaoSuave, shape: BoxShape.circle),
            child: Icon(icone, size: 40, color: c.acaoTexto),
          ),
          const SizedBox(height: 16),
          Text(titulo, style: t.titleMedium, textAlign: TextAlign.center),
          if (texto != null) ...[const SizedBox(height: 6), Text(texto!, style: t.bodySmall, textAlign: TextAlign.center)],
          if (acao != null) ...[const SizedBox(height: 20), SizedBox(width: 220, child: BotaoPrincipal(rotulo: acao!, aoTocar: aoTocarAcao))],
          if (rodape != null) ...[const SizedBox(height: 8), rodape!],
        ]),
      ),
    );
  }
}

class Carregando extends StatelessWidget {
  const Carregando({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Mostra erro com botão de tentar de novo.
class ErroNaTela extends StatelessWidget {
  const ErroNaTela({super.key, required this.erro, this.aoTentar});
  final Object erro;
  final VoidCallback? aoTentar;

  @override
  Widget build(BuildContext context) => EstadoVazio(
        icone: Symbols.cloud_off_rounded,
        titulo: 'Algo deu errado',
        texto: ErroIService.de(erro).mensagem,
        acao: aoTentar == null ? null : 'Tentar de novo',
        aoTocarAcao: aoTentar,
      );
}

void mostrarMensagem(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Mostra o erro. Se faltar confirmar o celular, oferece o atalho para a confirmação.
void mostrarErro(BuildContext context, Object erro) {
  final e = ErroIService.de(erro);
  if (e.codigo == 'celular_nao_verificado') {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(e.mensagem),
        action: SnackBarAction(label: 'Confirmar', onPressed: () => abrirConfirmacaoCelular(context)),
      ));
    return;
  }
  mostrarMensagem(context, e.mensagem);
}

/// Título de seção com link opcional ("Ver todos").
class TituloSecao extends StatelessWidget {
  const TituloSecao({super.key, required this.titulo, this.acao, this.aoTocarAcao, this.icone});
  final String titulo;
  final String? acao;
  final VoidCallback? aoTocarAcao;
  final Widget? icone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(children: [
          if (icone != null) ...[icone!, const SizedBox(width: 6)],
          Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleLarge)),
          if (acao != null)
            TextButton(
              onPressed: aoTocarAcao,
              child: Row(mainAxisSize: MainAxisSize.min, children: [Text(acao!), const Icon(Symbols.chevron_right_rounded, size: 20)]),
            ),
        ]),
      );
}

/// Etiqueta colorida do status do pedido.
class EtiquetaStatus extends StatelessWidget {
  const EtiquetaStatus({super.key, required this.status});
  final StatusPedido status;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (cor, fundo) = switch (status) {
      StatusPedido.solicitado => (c.alerta, c.alertaSuave),
      StatusPedido.aceito || StatusPedido.aCaminho || StatusPedido.emAtendimento => (c.acaoTexto, c.acaoSuave),
      StatusPedido.concluido => (c.sucesso, c.sucessoSuave),
      _ => (c.perigo, c.perigoSuave),
    };
    return Selo(texto: status.rotulo, cor: cor, fundo: fundo);
  }
}

/// Contagem regressiva mm:ss até [ate]. Chama [aoAcabar] uma vez.
class ContagemRegressiva extends StatefulWidget {
  const ContagemRegressiva({super.key, required this.ate, this.estilo, this.aoAcabar});
  final DateTime ate;
  final TextStyle? estilo;
  final VoidCallback? aoAcabar;

  @override
  State<ContagemRegressiva> createState() => _ContagemRegressivaState();
}

class _ContagemRegressivaState extends State<ContagemRegressiva> {
  Timer? _timer;
  bool _avisou = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_avisou && DateTime.now().isAfter(widget.ate)) {
        _avisou = true;
        widget.aoAcabar?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var r = widget.ate.difference(DateTime.now());
    if (r.isNegative) r = Duration.zero;
    final m = r.inMinutes.toString().padLeft(2, '0');
    final s = (r.inSeconds % 60).toString().padLeft(2, '0');
    return Text('$m:$s', style: widget.estilo, semanticsLabel: '${r.inMinutes} minutos e ${r.inSeconds % 60} segundos');
  }
}

/// Campo de seleção em lista (abre uma folha de baixo com as opções).
Future<T?> escolherEmLista<T>(BuildContext context, {required String titulo, required List<T> opcoes, required String Function(T) rotulo, T? atual}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .95,
      builder: (ctx, scroll) => Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(titulo, style: Theme.of(ctx).textTheme.titleLarge)),
        Expanded(
          child: ListView(controller: scroll, children: [
            for (final o in opcoes)
              ListTile(
                title: Text(rotulo(o)),
                trailing: o == atual ? Icon(Symbols.check_rounded, color: ctx.cores.acaoTexto) : null,
                onTap: () => Navigator.pop(ctx, o),
              ),
          ]),
        ),
      ]),
    ),
  );
}

/// Tela cheia com a imagem da marca: o profissional aparece no alto e vai escurecendo
/// até o azul da marca, onde ficam os textos.
class FundoMarca extends StatelessWidget {
  const FundoMarca({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: Cores.fundoMarca(escurecer: .35, alinhamento: Cores.focoFundo, imagem: Cores.imagemFundo),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .3, .55, 1],
              colors: [
                Cores.azulEscuro.withValues(alpha: .25),
                Cores.azulEscuro.withValues(alpha: .7),
                Cores.azulEscuro.withValues(alpha: .93),
                Cores.azulEscuro.withValues(alpha: .97),
              ],
            ),
          ),
          child: child,
        ),
      );
}
