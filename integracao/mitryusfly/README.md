# Suporte remoto Vetor no Mitryus Fly (Windows)

> **Para:** o agente do projeto `mitryus_app` (Mitryus Fly).
> **De:** projeto Suporte Vetor (`C:\VETOR\PROJETOS\Suporte_Remoto\vetorsuporte`), 25/11/2026.
> **Referência pronta e testada:** a unit Delphi `vetorsuporte\integracao\mitryusweb\LibSuporteVetor.pas`, que o MitryusWeb já usa. Este documento pede o **mesmo fluxo em Dart**, no Fly.

## 1. O que é e o que muda

O **Suporte Vetor Sistemas** é o acesso remoto próprio da Vetor, baseado no RustDesk, com servidor próprio. Ele vai tomar o lugar do LogMeIn Rescue no Windows.

O programa do lado do cliente é o **Cliente** (`SuporteVetorSistemas.exe`), instalado por um **MSI**. O técnico usa o **Console Técnico** e acessa pelo **ID** do computador, um número de 9 ou 10 dígitos.

**É o mesmo que o MitryusWeb já faz.** Quando o usuário chama o suporte:
1. O Fly verifica se o Cliente está instalado e atualizado. Se não estiver, baixa e instala.
2. O Fly lê o ID do computador e **libera o acesso por 10 minutos**, sem abrir a janela do Cliente.
3. O Fly abre o chat do PipeFly, como hoje, **passando o ID na URL**, no parâmetro **`id_acesso_remoto`**.

O PipeFly já aceita esse parâmetro desde 24/11/2026:
- ele aparece na ficha do chamado como "ID de acesso remoto", com um botão Copiar;
- se o cliente reabrir o portal com outro ID, o chamado é atualizado;
- veja `pipefly_mitryus/doc_ia/TICKETS.md`, nos parâmetros do portal.

O técnico copia o ID do chamado, cola no Console Técnico e conecta. No computador do cliente, aparece uma janela de aprovação, e o cliente clica em **Aceitar**. Sem a liberação, o Console recebe "O cliente não liberou o acesso" e nada aparece para o cliente.

**Escopo deste trabalho:**
- **O chat não muda.** O painel (`chat_suporte_painel.dart`), a página do PipeFly, o JS injetado e o botão do LogMeIn do técnico ficam exatamente como estão;
- **o que muda é a forma do acesso remoto:** antes de abrir o chat, o Fly prepara o Suporte Vetor e acrescenta o `id_acesso_remoto` à URL que ele já monta;
- **só Windows**, porque só existe MSI x64;
- macOS, Android, iOS e Linux continuam como estão;
- **não apague o código do LogMeIn.**

## 2. O que já existe no Fly (lido em 25/11/2026, branch `v2026`)

| Onde | O que faz hoje |
|---|---|
| `lib/domain/usuario/usuario.dart:764` `Usuario.chamarSuporteOnline` | Botões "Suporte Técnico": app bar, home, home v2, login, barra inferior, versão bloqueada → `DialogDadosSuporte` → `ChatSuportePainel.abrir(url do PipeFly)` |
| `lib/widgets/chat_suporte/chat_suporte_painel.dart` | Chat do PipeFly num webview. Quando o técnico pede acesso, o site baixa um `.txt`, o JS injetado manda `logmein:<1ª linha>` e `_abrirSuporteRemoto(codigo)` chama `UsuarioService.conectarSuporteComCodigo` (applet do LogMeIn) |
| `lib/pages/configuracoes/configuracoes_controller.dart:145` `onTapSuporteOnline` | Configurações > Suporte online. No desktop, baixa e abre o `Support-LogMeInRescue.exe` (`UsuarioService.downloadArquivoSuporte`) |
| `lib/services/usuario_service.dart:312-430` | Download e execução do applet do LogMeIn, gravado em `${getDirectory()}\suporte\` |

## 3. O que o Suporte Vetor publica (contrato que o Fly consome)

**Pasta do site:** `https://www.mitryusweb.com.br/MITRYUSWEB/SUPORTE/`. É a mesma do MitryusWeb, e está no ar com a 1.1.5.

`versao.json` (sempre com esse nome; sem BOM):

```json
{
  "numero": 20,
  "tag": "v1.1.5",
  "versao": "1.1.5",
  "rustdesk": "1.5.3",
  "suportevetorsistemas-msi": {
    "arquivo": "suporte-v1.1.5-client-x64.msi",
    "sha256": "0ee6e0e0c9389f49336677b2cf5f6d13375f97f0e72e2da2a226b805c7693a15"
  },
  "consoletecnicovetorsistemas": { "arquivo": "...", "sha256": "..." }
}
```

- Use só `versao` e a chave `suportevetorsistemas-msi` (`arquivo` e `sha256`). Ignore as outras chaves, porque podem aparecer chaves novas.
- O MSI fica em `<pasta do site><arquivo>`.
- **Nunca** fixe a versão nem o nome do MSI no código. Leia sempre do `versao.json`.

**Constantes fixas do Cliente (não mudam entre versões):**

| Constante | Valor |
|---|---|
| Nome interno (exe, pasta, serviço) | `SuporteVetorSistemas` |
| UpgradeCode do MSI | `{662564EC-9C68-51A1-9469-01C410A95CC9}` |
| Pasta de instalação gravada pelo MSI | `HKCR\.suportevetorsistemas`, valor `INSTALLFOLDER`; padrão: `C:\Program Files\SuporteVetorSistemas\` |
| Chave do instalador `.exe` antigo (anterior ao MSI) | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SuporteVetorSistemas` (`UninstallString`, `DisplayVersion`) |

**Linha de comando do Cliente (não precisa de administrador):**

| Comando | Resposta no stdout |
|---|---|
| `SuporteVetorSistemas.exe --get-id` | O ID numa linha só com dígitos. Logo depois de instalar pode vir vazio, enquanto o serviço sobe |
| `SuporteVetorSistemas.exe --vetor-liberar` | Libera por 10 minutos **sem abrir janela** e responde a hora do fechamento (segundos desde 1970, 9 a 12 dígitos). Vazio quer dizer que não liberou |
| `SuporteVetorSistemas.exe --uninstall` (como administrador) | Remove o Cliente antigo instalado pelo `.exe` |

> Não leia o arquivo de configuração (`.toml`) do Cliente: ele guarda a chave privada do computador. Use só os comandos acima.

## 4. O fluxo (igual ao `fSuporteVetorAbrir` do `.pas`)

1. **Só Windows de 64 bits.** No de 32 bits, mostre: "Este computador tem Windows de 32 bits. Peça ao suporte o instalador de 32 bits."
2. **O que está instalado:**
   - o exe vem de `INSTALLFOLDER`, ou da pasta padrão, se o arquivo existir;
   - a versão do MSI vem de `MsiEnumRelatedProductsW(UpgradeCode)` + `MsiGetProductInfoW(..., "VersionString")`;
   - se não houver MSI, mas existir a chave do `.exe` antigo, a versão é a `DisplayVersion` dela (ou `"0"`), e isso marca o **Cliente antigo**;
   - se o exe não existir, trate como **não instalado**.
3. **Versão do site:** baixe o `versao.json` com `?t=<timestamp>`, para fugir de cache.
4. **Precisa instalar** se não estiver instalado, ou se `versao` do site for maior que a instalada.
   - Compare número a número, até 4 partes: `1.1.5` é igual a `1.1.5.0`, porque o MSI acrescenta o quarto número.
   - Sem acesso ao site, mas já instalado: siga com a versão instalada.
   - Não instalado e sem site: mostre um erro.
5. **Baixar e conferir:**
   - baixe o MSI para `${await getDirectory()}\suporte\SuporteVetor\` (ver o item 7.1, sobre o MSIX);
   - confira o **SHA-256**. Se não bater, apague o arquivo e não instale. Se já estava instalado, siga com a versão antiga;
   - valide `arquivo` com `^[A-Za-z0-9._-]+$` e `sha256` com 64 caracteres hexadecimais, para o nome não virar caminho (`..\`).
6. **Cliente antigo (`.exe`):** o MSI se recusa a instalar por cima dele. Antes do MSI:
   - rode `SuporteVetorSistemas.exe --uninstall` **como administrador** (é um segundo UAC);
   - espere até 30 s a chave `Uninstall\SuporteVetorSistemas` sumir.
7. **Instalar como administrador:**
   - comando: `msiexec.exe /i "<msi>" /passive /norestart /l*v "<pasta>\instalacao.log"`;
   - use `ShellExecuteEx` com o verbo `runas` e espere o processo terminar sem travar a tela;
   - **a janela dona (`hwnd`) tem que ser a janela do Fly, visível e em primeiro plano.** Pegue o `GetForegroundWindow()` no clique e chame `SetForegroundWindow` antes do pedido. Sem isso, o Windows 11 deixa o UAC **minimizado, piscando na barra de tarefas**. Foi o bug corrigido no `.pas` em 25/11/2026;
   - códigos de saída do msiexec:
     - `0`, `3010` e `1641`: deu certo;
     - `1602`: o usuário cancelou;
     - `1618`: outra instalação em andamento;
     - qualquer outro: falhou, e o detalhe fica no log;
   - se o `ShellExecuteEx` falhar com `1223` (`ERROR_CANCELLED`), o usuário recusou o UAC: "A instalação do Suporte remoto precisa da permissão de administrador.";
   - se a atualização falhar, mas o exe antigo continuar lá, **siga com ele** e não mostre o erro;
   - depois de instalar, espere **3 s**, enquanto o serviço do Cliente sobe.
8. **ID:** `--get-id`, escondido, com até **6 tentativas, 2 s entre elas**. Pegue a **última linha só com dígitos**, de 6 a 12 caracteres. Use um timeout de 20 s por execução.
9. **Liberar:** `--vetor-liberar`, escondido. Liberou se houver uma linha só com dígitos, de 9 a 12 caracteres.
   - Só se não liberar, abra o Cliente normalmente (`Process.start(exe, [], mode: detached)`): abrir a janela também libera, mas cobre o Fly.
10. **Resultado:** devolva o ID para ele ir no `id_acesso_remoto` da URL do chat (seção 7). Sem ID, mas liberado: "O Suporte remoto foi aberto, mas não foi possível ler o ID. Informe ao suporte o ID que aparece na tela."
11. **Uma execução por vez:** um segundo clique durante o fluxo responde "O Suporte remoto já está sendo preparado. Aguarde."

## 5. Implementação de referência

Arquivo novo: **`lib/services/suporte_vetor_service.dart`**. Ajuste ao padrão do projeto (`@injectable`, `ServiceResponse` etc.), mas mantenha a lógica.

**`pubspec.yaml`:** promova a dependência direta o que já vem por transitividade, nas mesmas versões do `pubspec.lock`:

```yaml
  win32: ^5.15.0
  win32_registry: ^1.1.5
```

O `ffi`, o `crypto`, o `dio` e o `path_provider` já são diretos.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

import '../utils/pages.dart'; // getDirectory()

class SuporteVetorResultado {
  final bool ok;
  final String id;
  final String erro;
  const SuporteVetorResultado.sucesso(this.id)
      : ok = true,
        erro = '';
  const SuporteVetorResultado.falha(this.erro, {this.id = ''}) : ok = false;
}

/// Suporte remoto Vetor (Windows): instala/atualiza o Cliente pelo MSI do site,
/// lê o ID e libera o acesso por 10 minutos sem abrir a janela do Cliente.
/// Port do LibSuporteVetor.pas (MitryusWeb).
class SuporteVetorService {
  static const urlBase = 'https://www.mitryusweb.com.br/MITRYUSWEB/SUPORTE/';
  static const arqVersao = 'versao.json';
  static const nomeApp = 'SuporteVetorSistemas';
  static const chaveMsi = 'suportevetorsistemas-msi';
  static const upgradeCode = '{662564EC-9C68-51A1-9469-01C410A95CC9}';
  static const msiModo = '/passive'; // só a barra de progresso
  static const _chaveDesinstalar =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + nomeApp;
  static const _seeMaskNoCloseProcess = 0x00000040; // não vem no pacote win32

  static bool _ocupado = false;

  /// O botão só deve aparecer quando isto for verdadeiro.
  static bool get disponivel => Platform.isWindows;

  /// Dio próprio, sem os interceptors do CustomDio (o site é estático).
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));

  Future<SuporteVetorResultado> abrir({void Function(String)? etapa}) async {
    if (!Platform.isWindows) {
      return const SuporteVetorResultado.falha(
          'O Suporte remoto Vetor só está disponível no Windows.');
    }
    if (_ocupado) {
      return const SuporteVetorResultado.falha(
          'O Suporte remoto já está sendo preparado. Aguarde.');
    }
    _ocupado = true;
    // Janela do Fly no momento do clique: dona do pedido do UAC.
    final dona = GetForegroundWindow();
    try {
      return await _fluxo(dona, etapa ?? (_) {});
    } catch (e) {
      return SuporteVetorResultado.falha('Erro ao preparar o Suporte remoto: $e');
    } finally {
      _ocupado = false;
    }
  }

  Future<SuporteVetorResultado> _fluxo(int dona, void Function(String) etapa) async {
    if (!_windows64()) {
      return const SuporteVetorResultado.falha('Este computador tem Windows de 32 bits. '
          'Peça ao suporte o instalador de 32 bits.');
    }

    // 1. O que está instalado
    etapa('Verificando o Suporte remoto...');
    var exe = exeInstalado();
    final verMsi = versaoInstalada();
    final verExe = verMsi.isEmpty ? versaoInstaladaPeloExe() : '';
    var verAtual = verMsi.isNotEmpty ? verMsi : verExe;
    if (exe.isEmpty) verAtual = ''; // registro sem o programa: instala de novo

    final pasta = Directory('${await getDirectory()}\\suporte\\SuporteVetor');
    await pasta.create(recursive: true);

    // 2. Versão publicada no site
    etapa('Procurando versão nova...');
    var verWeb = '', arquivo = '', hash = '';
    try {
      final r = await _dio.get<String>(
        '$urlBase$arqVersao',
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(responseType: ResponseType.plain),
      );
      final j = jsonDecode(r.data ?? '') as Map<String, dynamic>;
      verWeb = '${j['versao'] ?? ''}';
      final m = j[chaveMsi];
      if (m is Map) {
        arquivo = '${m['arquivo'] ?? ''}';
        hash = '${m['sha256'] ?? ''}'.toLowerCase();
      }
      if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(arquivo) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        arquivo = '';
        hash = '';
      }
    } catch (_) {
      // sem site: decide abaixo
    }

    // 3. Instalar ou atualizar
    final precisa = verAtual.isEmpty ||
        (verWeb.isNotEmpty && compararVersoes(verWeb, verAtual) > 0);
    if (precisa) {
      if (verWeb.isEmpty || arquivo.isEmpty) {
        if (exe.isEmpty) {
          return const SuporteVetorResultado.falha(
              'Não foi possível consultar a página do Suporte remoto ($urlBase). '
              'Verifique a internet e tente de novo.');
        }
        // sem site, mas instalado: segue com a versão que está aí
      } else {
        etapa('Baixando o Suporte remoto $verWeb...');
        final msi = await _baixarMsi(pasta, arquivo, hash, etapa, verWeb);
        if (msi == null) {
          if (exe.isEmpty) {
            return const SuporteVetorResultado.falha(
                'Não foi possível baixar o Suporte remoto, ou o arquivo baixado '
                'não confere (SHA-256). Tente de novo mais tarde.');
          }
        } else {
          // O MSI recusa instalar por cima do Cliente instalado pelo .exe
          if (verExe.isNotEmpty && exe.isNotEmpty) {
            etapa('Removendo a versão antiga do Suporte remoto...');
            await _executarElevado(dona, exe, '--uninstall');
            for (var i = 0; i < 30; i++) {
              if (_lerRegistro(RegistryHive.localMachine, _chaveDesinstalar,
                      'UninstallString')
                  .isEmpty) break;
              await Future.delayed(const Duration(seconds: 1));
            }
          }

          etapa('Instalando o Suporte remoto $verWeb...');
          final log = '${pasta.path}\\instalacao.log';
          final (iniciou, codigo) = await _executarElevado(
              dona, 'msiexec.exe', '/i "${msi.path}" $msiModo /norestart /l*v "$log"');
          var erro = '';
          if (!iniciou) {
            erro = codigo == ERROR_CANCELLED
                ? 'A instalação do Suporte remoto precisa da permissão de administrador.'
                : 'Não foi possível iniciar a instalação (erro $codigo).';
          } else if (codigo == 1602) {
            erro = 'A instalação do Suporte remoto foi cancelada.';
          } else if (codigo == 1618) {
            erro = 'Há outra instalação em andamento no Windows. '
                'Aguarde ela terminar e tente de novo.';
          } else if (!(codigo == 0 || codigo == 3010 || codigo == 1641)) {
            erro = 'A instalação do Suporte remoto falhou (código $codigo). '
                'Detalhes em $log';
          }

          exe = exeInstalado();
          if (exe.isEmpty) {
            return SuporteVetorResultado.falha(erro.isNotEmpty
                ? erro
                : 'O Suporte remoto não foi encontrado depois da instalação.');
          }
          // Falhou a atualização, mas a versão anterior continua lá: segue.
          await Future.delayed(const Duration(seconds: 3)); // serviço subindo
        }
      }
    }

    if (exe.isEmpty) {
      return const SuporteVetorResultado.falha('O Suporte remoto não está instalado.');
    }

    // 4. ID (o serviço pode estar subindo)
    etapa('Lendo o ID deste computador...');
    var id = '';
    for (var i = 0; i < 6 && id.isEmpty; i++) {
      if (i > 0) await Future.delayed(const Duration(seconds: 2));
      id = _linhaNumerica(await _executarOculto(exe, '--get-id'), 6, 12);
    }

    // 5. Libera 10 min sem abrir a janela. Sem resposta: abre a janela (também libera).
    etapa('Liberando o acesso ao suporte...');
    final liberou =
        _linhaNumerica(await _executarOculto(exe, '--vetor-liberar'), 9, 12).isNotEmpty;
    if (!liberou) {
      try {
        await Process.start(exe, const [],
            workingDirectory: File(exe).parent.path, mode: ProcessStartMode.detached);
      } catch (_) {
        return SuporteVetorResultado.falha(
            'Não foi possível liberar o acesso nem abrir $exe');
      }
    }

    if (id.isEmpty) {
      return const SuporteVetorResultado.falha(
          'O Suporte remoto foi aberto, mas não foi possível ler o ID. '
          'Informe ao suporte o ID que aparece na tela.');
    }
    return SuporteVetorResultado.sucesso(id);
  }

  // ---------------------------------------------------------------- instalado

  String exeInstalado() {
    var pasta = _lerRegistro(
        RegistryHive.classesRoot, '.${nomeApp.toLowerCase()}', 'INSTALLFOLDER');
    if (pasta.isEmpty) {
      final pf = Platform.environment['ProgramW6432'] ??
          Platform.environment['ProgramFiles'] ??
          r'C:\Program Files';
      pasta = '$pf\\$nomeApp';
    }
    if (!pasta.endsWith('\\')) pasta += '\\';
    final exe = '$pasta$nomeApp.exe';
    return File(exe).existsSync() ? exe : '';
  }

  /// Versão do MSI instalado (ex.: '1.1.5.0'), ou ''.
  String versaoInstalada() {
    final up = upgradeCode.toNativeUtf16();
    final produto = calloc<Uint16>(39).cast<Utf16>();
    final atributo = 'VersionString'.toNativeUtf16();
    final buf = calloc<Uint16>(64).cast<Utf16>();
    final tam = calloc<Uint32>()..value = 64;
    try {
      if (_msiEnumRelatedProducts(up, 0, 0, produto) != 0) return '';
      if (_msiGetProductInfo(produto, atributo, buf, tam) != 0) return '';
      return buf.toDartString();
    } finally {
      calloc
        ..free(up)
        ..free(produto)
        ..free(atributo)
        ..free(buf)
        ..free(tam);
    }
  }

  /// Versão de um Cliente antigo, instalado pelo .exe, ou ''.
  String versaoInstaladaPeloExe() {
    if (_lerRegistro(RegistryHive.localMachine, _chaveDesinstalar, 'UninstallString')
        .isEmpty) return '';
    final v =
        _lerRegistro(RegistryHive.localMachine, _chaveDesinstalar, 'DisplayVersion');
    return v.isEmpty ? '0' : v;
  }

  /// 1 se a > b, -1 se a < b, 0 se iguais ('1.1.5' == '1.1.5.0').
  static int compararVersoes(String a, String b) {
    List<int> partes(String s) {
      final p = s.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
      while (p.length < 4) {
        p.add(0);
      }
      return p;
    }

    final x = partes(a), y = partes(b);
    for (var i = 0; i < 4; i++) {
      if (x[i] != y[i]) return x[i] > y[i] ? 1 : -1;
    }
    return 0;
  }

  // ---------------------------------------------------------------- download

  Future<File?> _baixarMsi(Directory pasta, String arquivo, String hash,
      void Function(String) etapa, String versao) async {
    final destino = File('${pasta.path}\\$arquivo');
    if (await destino.exists() && await _sha256(destino) == hash) return destino;
    final parte = File('${destino.path}.parte');
    try {
      await _dio.download('$urlBase$arquivo', parte.path,
          onReceiveProgress: (recebido, total) {
        if (total > 0) {
          etapa('Baixando o Suporte remoto $versao... ${recebido * 100 ~/ total}%');
        }
      });
    } catch (_) {
      if (await parte.exists()) await parte.delete();
      return null;
    }
    if (await _sha256(parte) != hash) {
      await parte.delete();
      return null;
    }
    if (await destino.exists()) await destino.delete();
    return parte.rename(destino.path);
  }

  Future<String> _sha256(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  // ---------------------------------------------------------------- processos

  /// Roda escondido e devolve o stdout (o Cliente é um exe GUI: não pisca janela).
  Future<String> _executarOculto(String exe, String argumento) async {
    try {
      final p = await Process.start(exe, [argumento],
          workingDirectory: File(exe).parent.path);
      final saida = p.stdout.transform(systemEncoding.decoder).join();
      unawaited(p.stderr.drain<void>());
      await p.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
        p.kill();
        return -1;
      });
      return await saida.timeout(const Duration(seconds: 2), onTimeout: () => '');
    } catch (_) {
      return '';
    }
  }

  /// Última linha só com dígitos, com min a max caracteres, ou ''.
  static String _linhaNumerica(String saida, int min, int max) {
    final linhas = const LineSplitter().convert(saida).reversed;
    for (final l in linhas) {
      final t = l.trim();
      if (t.length >= min && t.length <= max && RegExp(r'^\d+$').hasMatch(t)) return t;
    }
    return '';
  }

  /// ShellExecuteEx "runas" com a janela do Fly como dona (o UAC abre na frente)
  /// e espera terminar sem travar a tela. Devolve (iniciou, código).
  Future<(bool, int)> _executarElevado(int dona, String arquivo, String parametros) async {
    final sei = calloc<SHELLEXECUTEINFO>();
    final verbo = 'runas'.toNativeUtf16();
    final arq = arquivo.toNativeUtf16();
    final par = parametros.toNativeUtf16();
    final codigo = calloc<Uint32>();
    try {
      sei.ref
        ..cbSize = sizeOf<SHELLEXECUTEINFO>()
        ..fMask = _seeMaskNoCloseProcess
        ..hwnd = dona
        ..lpVerb = verbo
        ..lpFile = arq
        ..lpParameters = par
        ..nShow = SW_SHOWNORMAL;
      if (dona != 0) SetForegroundWindow(dona);
      if (ShellExecuteEx(sei) == 0) return (false, GetLastError());
      final processo = sei.ref.hProcess;
      if (processo == 0) return (true, 0);
      try {
        while (WaitForSingleObject(processo, 0) == WAIT_TIMEOUT) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
        GetExitCodeProcess(processo, codigo);
        return (true, codigo.value);
      } finally {
        CloseHandle(processo);
      }
    } finally {
      calloc
        ..free(sei)
        ..free(verbo)
        ..free(arq)
        ..free(par)
        ..free(codigo);
    }
  }

  // ---------------------------------------------------------------- utilitários

  static String _lerRegistro(RegistryHive raiz, String chave, String valor) {
    try {
      final k = Registry.openPath(raiz, path: chave);
      try {
        return k.getValueAsString(valor) ?? '';
      } finally {
        k.close();
      }
    } catch (_) {
      return ''; // chave inexistente
    }
  }

  static bool _windows64() {
    final e = Platform.environment;
    final arq = (e['PROCESSOR_ARCHITEW6432'] ?? e['PROCESSOR_ARCHITECTURE'] ?? '')
        .toUpperCase();
    return arq.contains('64');
  }
}

// msi.dll (não está no pacote win32). `final` de topo é preguiçoso: só abre no Windows.
final _msi = DynamicLibrary.open('msi.dll');
final _msiEnumRelatedProducts = _msi.lookupFunction<
    Uint32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Utf16>),
    int Function(Pointer<Utf16>, int, int, Pointer<Utf16>)>('MsiEnumRelatedProductsW');
final _msiGetProductInfo = _msi.lookupFunction<
    Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>),
    int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
        Pointer<Uint32>)>('MsiGetProductInfoW');
```

> Esse código **não foi compilado** dentro do Fly. Ele segue as APIs do `win32` 5.15.0 e do `win32_registry` 1.1.5 que estão no `pubspec.lock`. Rode o `flutter analyze` e corrija o que for preciso.
> O `GetLastError()` lido pelo Dart depois do FFI pode não ser confiável. Se o código do UAC recusado não vier como 1223, trate qualquer falha do `ShellExecuteEx` como "precisa da permissão de administrador".

## 6. Tela

Só um **diálogo de andamento**, enquanto o serviço trabalha, antes de o chat abrir.
- Use o padrão do projeto (`DialogLoading`, ou um diálogo no visual do `DialogDadosSuporte`).
- Mostre o texto da etapa atual: é o callback `etapa`, num `ValueNotifier<String>`, com mensagens como "Baixando o Suporte remoto 1.1.5... 40%" e "Instalando...".
- Não deixe fechar com o fluxo em andamento.

Não precisa de tela para mostrar o ID: ele vai na URL do chat e aparece para o técnico no chamado.

**Se o fluxo falhar** (UAC recusado, sem internet etc.):
- **abra o chat do mesmo jeito**, sem o `id_acesso_remoto`. O suporte não pode ficar bloqueado por causa do acesso remoto;
- mostre a mensagem do serviço num `SnackBar`, ou num aviso que não impeça o chat de abrir.

**Não abra a janela do Cliente** no caminho normal: o `--vetor-liberar` existe justamente para não cobrir o Fly.

Função de entrada sugerida:

```dart
/// Prepara o Suporte Vetor (instala/atualiza, lê o ID, libera 10 min) mostrando
/// o andamento. Retorna o ID, ou '' se não conseguiu. Fora do Windows, retorna '' na hora.
Future<String> prepararSuporteRemotoVetor(BuildContext context);
```

## 7. Onde ligar: ao chamar o suporte, antes de abrir o chat

Crie uma constante, por exemplo em `ConfiguracaoConexao`, para poder desligar sem mexer no código:

```dart
/// Windows: prepara o Suporte Vetor e manda o id_acesso_remoto ao chat.
static const bool suporteRemotoVetor = true;
```

**O ponto é `Usuario.chamarSuporteOnline`** (`lib/domain/usuario/usuario.dart:764`). Todos os botões "Suporte Técnico" passam por ele: app bar, home, home v2, login, barra inferior e versão bloqueada.

```dart
static Future<void> chamarSuporteOnline(BuildContext context) async {
  if (!context.mounted) return;

  if (ChatSuportePainel.aberto) {
    // Chat já aberto: renova a liberação de 10 min (rápido, já está instalado),
    // sem recarregar o chat. O ID não muda.
    if (ConfiguracaoConexao.suporteRemotoVetor && SuporteVetorService.disponivel) {
      unawaited(SuporteVetorService().abrir());
    }
    ChatSuportePainel.restaurar();
    return;
  }

  final grupo = await _grupoParaSuporte();
  if (!context.mounted) return;

  final dados = await DialogDadosSuporte.abrir(
    context,
    nomeInicial: getUsuario()?.nomeUsuario ?? '',
    grupoInicial: grupo,
  );
  if (dados == null || !context.mounted) return;

  // NOVO: instala/atualiza o Cliente, lê o ID e libera 10 min (só Windows).
  var idAcessoRemoto = '';
  if (ConfiguracaoConexao.suporteRemotoVetor && SuporteVetorService.disponivel) {
    idAcessoRemoto = await prepararSuporteRemotoVetor(context); // '' se falhar
    if (!context.mounted) return;
  }

  ChatSuportePainel.abrir(
    context,
    _montarUrlSuporte(
      nome: dados.nome,
      telefone: dados.telefone,
      grupo: dados.grupo,
      idAcessoRemoto: idAcessoRemoto, // NOVO
    ),
  );
}
```

### A URL do chat: fica como está hoje, mais um parâmetro

**Regra:** a geração da URL em `Usuario._montarUrlSuporte` (`usuario.dart:814`) **continua exatamente como está hoje**. A única mudança é acrescentar **um parâmetro novo, `id_acesso_remoto`**, no fim.

Ficam como estão, sem nenhuma mudança:
- o host e o caminho (`ConfiguracaoConexao.hostSuporteChat` + `pathSuporteChat`);
- os parâmetros `grupo`, `loja`, `nome`, `codigo`, `terminal`, `telefone`, `versao`, `sistema` e `usuario_adm`: os mesmos nomes, a mesma ordem e o mesmo formato. A `loja` continua com 2 dígitos, o `codigo` e o `terminal` sem zeros à esquerda, e o `sistema` continua `MitryusFly`;
- o `Uri.encodeQueryComponent` e a forma de juntar a query.

O que muda em `_montarUrlSuporte`:

```dart
static String _montarUrlSuporte({
  required String nome,
  required String telefone,
  required String grupo,
  String idAcessoRemoto = '', // NOVO, opcional
}) {
  // ... tudo como hoje ...
  final params = <String, String>{
    // ... exatamente os mesmos de hoje, sem mudar nada ...
    if (idAcessoRemoto.isNotEmpty) 'id_acesso_remoto': idAcessoRemoto, // NOVO
  };
  // ... tudo como hoje ...
}
```

- **Valor:** só os dígitos do ID que o `SuporteVetorService` devolveu, sem máscara e sem espaços.
- **Sem ID** (falha, ou fora do Windows): o parâmetro **não vai**, e a URL fica idêntica à de hoje.

**Referência:** é o mesmo parâmetro que o MitryusWeb já manda no fim da URL dele (`... '&id_acesso_remoto=' + Trim(G_RMT_ID)`). O formato dos outros parâmetros do MitryusWeb é diferente do Fly, e isso **não** deve ser copiado. O `terminal`, por exemplo, é o que separa os chamados por computador no PipeFly.

**Por que depois do `DialogDadosSuporte`, e não antes:**
- o UAC e o download só acontecem quando o usuário confirmou que quer o suporte;
- se ele cancelar o diálogo, nada é instalado.

**Configurações > Suporte online** (`configuracoes_controller.dart`, `_executarSuporteDesktop`) continua com o LogMeIn como está. A troca desse ponto fica para quando a Vetor decidir desligar o LogMeIn.

**Fora do escopo** (não fazer):
- mudanças no painel do chat (`chat_suporte_painel.dart`), no JS injetado e na interceptação do `.txt` do LogMeIn;
- mudanças na página do PipeFly, que já trata o `id_acesso_remoto`;
- botões novos.

## 8. Cuidados (MSIX)

O Fly é empacotado como MSIX (`runFullTrust`), na Store e por sideload. Pontos a respeitar:

1. **Pasta do download:** use `getDirectory()`, que é a pasta Documentos e é a mesma do LogMeIn.
   - **Não** use `getTemporaryDirectory()` nem `getApplicationSupportDirectory()`. Num app MSIX, o que é gravado no AppData vai para uma pasta privada do pacote, e o `msiexec` elevado roda fora do pacote e pode não achar o arquivo.
2. **Registro e Program Files:** só leitura. O app MSIX enxerga o registro e os arquivos reais.
3. **Processos filhos rodam no contexto do pacote.** Por isso, a primeira coisa a testar é se o `--get-id` e o `--vetor-liberar`, chamados de dentro do Fly empacotado, respondem como no Delphi. Eles falam com o serviço do Cliente por IPC.
   - Se não responderem, avise o projeto Suporte Vetor antes de inventar um contorno.
   - Teste também no `flutter run`, sem MSIX, para separar o problema.
4. **Store:** o Fly da Store já baixa e executa o applet do LogMeIn. Instalar um MSI é o mesmo tipo de ação, mas vale conferir a política da Store antes de publicar a versão da Store.
5. **AGPL:** o Fly só baixa e executa o Cliente. Não copie nem ligue código do Suporte Vetor ao Fly, e nada muda na licença do Fly.

## 9. O que **não** fazer

- Não embutir o MSI no Fly nem fixar a versão ou o nome do arquivo: tudo vem do `versao.json`.
- Não usar `/qn` sem o `runas`: sem elevação, a instalação falha em silêncio.
- Não ler o `.toml` do Cliente nem gravar opções nele.
- Não abrir a janela do Cliente no caminho normal: só como alternativa, quando o `--vetor-liberar` não responder.
- Não mudar o chat: nem o painel, nem a página do PipeFly, nem o JS injetado.
- Não mexer na geração da URL do chat além de acrescentar o `id_acesso_remoto`: nada de renomear, reordenar, preencher com zeros ou mudar valores dos parâmetros de hoje.
- Não apagar o código do LogMeIn.
- Não impedir o chat de abrir quando o Suporte Vetor falhar.
- Não usar o `CustomDio`, que tem interceptors e o `baseUrl` da API, para o site do Suporte.

## 10. Testes (numa VM Windows 10/11 x64; nunca na máquina de trabalho)

| # | Cenário | Esperado |
|---|---|---|
| 1 | Sem o Cliente | Baixa, confere o SHA-256, mostra **um** UAC **na frente** do Fly, instala, mostra o ID e libera. Nenhuma janela do Cliente cobre o Fly |
| 2 | Cliente atual (1.1.5) instalado | Não baixa nada. Mostra o ID em poucos segundos e libera |
| 3 | Cliente MSI mais antigo, por exemplo a 1.1.3 | Atualiza: um UAC, e a versão nova aparece em "Adicionar/Remover programas" |
| 4 | Cliente antigo pelo `.exe` (1.1.2 ou anterior) | Dois UACs: remove e instala. Termina com o MSI |
| 5 | UAC recusado, sem o Cliente | Mensagem "precisa da permissão de administrador". O Fly continua normal |
| 6 | UAC recusado, com uma versão antiga instalada | Segue com a antiga, mostra o ID e libera |
| 7 | Sem internet, com o Cliente instalado | Segue com o instalado |
| 8 | Sem internet, sem o Cliente | Mensagem de que não conseguiu consultar a página |
| 9 | Dois cliques seguidos no botão | O segundo responde "já está sendo preparado" |
| 10 | Liberação de verdade | Do Console Técnico, conectar no ID **dentro** dos 10 min aparece a janela Aceitar. **Depois** de 10 min, sem clicar de novo, o Console mostra "O cliente não liberou o acesso" |
| 11 | Fly empacotado (MSIX sideload) | Repetir os cenários 1, 2 e 10 |
| 12 | Chamar o suporte no Windows | Depois do `DialogDadosSuporte`, aparece o andamento, e o chat abre com o `id_acesso_remoto` na URL. No PipeFly, o chamado mostra "ID de acesso remoto" com o botão Copiar. Comparando com a URL de antes da mudança, a única diferença é `&id_acesso_remoto=<ID>` no fim, e o chamado do computador continua o mesmo (mesmo `terminal`) |
| 13 | Cancelar o `DialogDadosSuporte` | Nada é baixado nem instalado |
| 14 | Falha (UAC recusado ou sem internet, sem o Cliente) | O chat abre normalmente, sem o `id_acesso_remoto`, e aparece um aviso |
| 15 | Chat já aberto, chamar o suporte de novo | O chat só é restaurado, e a liberação é renovada por mais 10 min |
| 16 | `suporteRemotoVetor = false` | Tudo igual a hoje |
| 17 | macOS, Android e iOS | Tudo igual a hoje |

Para o teste 10, peça ao projeto Suporte Vetor o Console Técnico (`suporte-vX.Y.Z-console-x64.exe`) e um login.

## 11. Entrega

- Arquivos novos:
  - `lib/services/suporte_vetor_service.dart`;
  - o diálogo de andamento com o `prepararSuporteRemotoVetor`.
- Alterados:
  - `pubspec.yaml`;
  - `configuracao_conexao.dart` (a constante);
  - `lib/domain/usuario/usuario.dart`: `chamarSuporteOnline` e `_montarUrlSuporte`. O `chat_suporte_painel.dart` não muda.
- Rode `flutter analyze`, e o `build_runner` se mexer em `@injectable`.
- Changelog no padrão do projeto (`/versao/`).
- Devolva ao projeto Suporte Vetor:
  - o resultado da tabela de testes;
  - em especial, o item 8.3 (`--get-id` e `--vetor-liberar` de dentro do MSIX) e o item 10 (UAC na frente).
