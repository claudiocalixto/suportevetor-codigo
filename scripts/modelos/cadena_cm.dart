// Vetor (2026-11-23): janela de aprovacao do Cliente (processo --cm do RustDesk). Ganha no topo as informacoes da
// tela principal (logo da marca, o ID deste computador e os servidores que respondem) e abre AO LADO da janela
// principal, em vez do canto superior direito da tela. A principal e outro processo: o Rust a acha pelo titulo e
// move a janela de aprovacao (ver "cadena-cm-ao-lado" no main_set_common). O 2_marca.ps1 copia este arquivo para
// flutter/lib/desktop/pages/cadena_cm.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

/// Chamada pelo main.dart logo depois que o RustDesk poe a janela de aprovacao no canto superior direito: no
/// Cliente, leva a janela para o lado da janela principal. Sem a principal aberta na tela, fica onde o RustDesk pos.
void cadenaCmAoLado() {
  if (!isWindows || !bind.isIncomingOnly()) return;
  bind.mainSetCommon(key: 'cadena-cm-ao-lado', value: '');
}

/// Chamada pelo main.dart ao abrir a janela principal, logo depois de restaurar a posicao salva: no Cliente, a janela
/// abre sempre no canto superior direito da area de trabalho do monitor dela, para nao cobrir o ERP no centro da tela
/// (ver "cadena-principal-canto" no main_set_common). A janela de aprovacao vai entao para a esquerda dela.
/// Ao voltar da bandeja (outra instancia acha a janela escondida e chama ShowWindow, sem passar pelo Dart), o evento
/// "show" do window_manager leva a janela de novo para o canto, a nao ser que o usuario a tenha arrastado neste
/// processo ("moved" so vem no fim de um arraste, WM_EXITSIZEMOVE; o SetWindowPos do Rust nao o dispara). Ao abrir
/// o programa de novo, vale o canto outra vez.
void cadenaPrincipalNoCanto() {
  if (!isWindows || !bind.isIncomingOnly()) return;
  bind.mainSetCommon(key: 'cadena-principal-canto', value: '');
  if (_cadenaCanto == null) {
    _cadenaCanto = _CadenaCantoAoMostrar();
    windowManager.addListener(_cadenaCanto!);
  }
}

_CadenaCantoAoMostrar? _cadenaCanto;

class _CadenaCantoAoMostrar with WindowListener {
  bool _movidaPeloUsuario = false;

  @override
  void onWindowMoved() => _movidaPeloUsuario = true;

  @override
  void onWindowShow() {
    if (!_movidaPeloUsuario) {
      bind.mainSetCommon(key: 'cadena-principal-canto', value: '');
    }
  }
}

/// Topo da janela de aprovacao do Cliente: logo, "Seu ID" e o status dos servidores
class CadenaCmMarca extends StatefulWidget {
  const CadenaCmMarca({Key? key}) : super(key: key);

  @override
  State<CadenaCmMarca> createState() => _CadenaCmMarcaState();
}

class _CadenaCmMarcaState extends State<CadenaCmMarca> {
  final _id = ''.obs;
  final _servidores = RxnString();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    bind.mainGetMyId().then((v) => _id.value = v);
    _ler();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _ler());
  }

  Future<void> _ler() async {
    final s = await bind.mainGetCommon(key: 'cadena-servidores');
    if (mounted) _servidores.value = s;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final suave =
        Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.75) ??
            Colors.grey;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).hoverColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Image.asset(escuro ? 'assets/logo_dark.png' : 'assets/logo_light.png',
            height: 34, fit: BoxFit.contain),
        const SizedBox(height: 10),
        Obx(() => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Seu ID  ', style: TextStyle(fontSize: 12, color: suave)),
                SelectableText(
                  _id.value.isEmpty ? '...' : formatID(_id.value),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1),
                ),
              ],
            )),
        Obx(() {
          final s = _servidores.value;
          final semServidor = s != null && s.isEmpty;
          final texto = s == null
              ? 'Verificando servidores...'
              : (semServidor
                  ? 'Sem conexão com o servidor'
                  : 'Conectado de forma segura · $s');
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: semServidor
                      ? const Color(0xFFE04F5F)
                      : (s == null ? Colors.orange : Colors.green),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(texto,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: suave)),
              ),
            ],
          ).paddingOnly(top: 6);
        }),
      ]),
    );
  }
}
