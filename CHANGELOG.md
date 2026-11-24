# Mudanças

## 1.1.4

### Cliente: janela principal no canto superior direito

A janela do Cliente abria no meio da tela, ou onde tinha sido fechada, e cobria o ERP.

- **Agora:** ela abre sempre no **canto superior direito da área de trabalho**, sem cobrir a barra de tarefas. Vale para o monitor onde a janela está, ou para o principal.
- A janela de aprovação continua abrindo ao lado da principal. Como à direita não há espaço, ela vai para a esquerda.
- **Como funciona:**
  - o `main.dart` chama `cadenaPrincipalNoCanto()` (`scripts/modelos/cadena_cm.dart`) logo depois do `restoreWindowPosition`;
  - a função chama o Rust pela chave `cadena-principal-canto` do `main_set_common`, que posiciona a janela com `SetWindowPos` em pixels reais, como já é feito com a janela de aprovação.
- Só no Cliente e só no Windows. O Técnico e o Console continuam como estavam.

## 1.1.3 (número interno 18)

Compilada em 24/11/2026 só para Windows de 64 bits: Console, Cliente (`.exe` e `.msi`) e portáteis. **Sem Android e sem o Cliente x86**, porque a máquina de compilação nova ainda não tem a distro WSL (`1_criar_wsl.ps1`) nem as ferramentas de 32 bits (`x86_ferramentas.ps1`). A versão do MSI é `1.1.3.<revisão>`, e a unit do MitryusWeb a considera igual à `1.1.3` do `versao.json`.

### Cliente: `--vetor-liberar`, liberação sem abrir a janela

Até a 1.1.2, o ERP só conseguia liberar o acesso abrindo a janela do Cliente, que cobria a tela do ERP.

- **Comando novo:** `SuporteVetorSistemas.exe --vetor-liberar`. Ele libera o acesso por **10 minutos** sem abrir janela nenhuma, e o Cliente continua na bandeja.
  - Grava a mesma opção que a janela grava (`cadena-liberado-ate`) nas opções do serviço, via IPC, sem administrador.
  - Responde no stdout com a hora do fechamento (segundos desde 1970). Saída vazia quer dizer que não liberou, por exemplo com o serviço parado.
  - Só vale no Cliente (incoming-only). No Técnico e no Console, não faz nada.
- Quando o técnico conecta, aparece só a **janela de aprovação**, com o botão Aceitar. O clique do cliente continua obrigatório.
- **Onde fica:** no `2_marca.ps1`, uma troca no `src/core_main.rs`, ao lado do `--get-id`.

### Integração com o MitryusWeb (Delphi 2007)

- **Pasta nova [`integracao/mitryusweb`](integracao/mitryusweb):** a unit `uSuporteVetor.pas` faz o botão "Suporte remoto" do ERP. Ela:
  1. confere se o Cliente está instalado e em que versão, pelo UpgradeCode do MSI;
  2. compara com o `versao.json` do site do MitryusWeb;
  3. baixa o MSI, confere o SHA-256 e instala ou atualiza;
  4. lê o ID com `--get-id`;
  5. libera o acesso com `--vetor-liberar`.
- **No site**, a cada versão: o `.msi` e o `versao.json` da pasta `publicar\vX.Y.Z`.
- O `.gitattributes` faz o checkout dos `.pas` em Windows-1252, que é o que o Delphi 2007 lê.

## 1.1.2 (número interno 17)

Junta tudo o que está na 1.1.1 abaixo e acrescenta o MSI do Cliente.

### Cliente também em MSI

O provedor onde ficam os instaladores para o ERP baixar não aceita `.exe`. Por isso, o Cliente também sai como **`suporte-vX.Y.Z-client-x64.msi`**.

- **Script novo `scripts/6_msi_cliente.ps1`**, chamado pelo `8_compilar_perfis.ps1` logo depois do Cliente. Ele usa o projeto WiX v4 do próprio RustDesk (`res/msi`) sobre a pasta compilada do Cliente:
  1. copia a pasta `Release` para `<Raiz>\msi-cliente`, renomeia `rustdesk.exe` para o nome interno (`SuporteVetorSistemas.exe`) e inclui o certificado **público** da marca (`cadena-editor.cer`);
  2. roda o `preprocess.py` com `--app-name`, `-v <versão>`, `-m <empresa>`, `-c` e `--conn-type incoming`;
  3. aplica as mudanças da Vetor no projeto:
     - **sem o assistente nem o acordo de licença** do RustDesk, que é em inglês: tira o `ui:WixUI` e a `InstallUISequence`. A instalação mostra só o progresso e o pedido de administrador;
     - **certificado da marca como confiável:** as ações `CadenaCertificadoRoot` e `CadenaCertificadoEditor` rodam `certutil -addstore` em Root e TrustedPublisher, como sistema, logo depois de `InstallFiles`. Falha não interrompe a instalação. É o mesmo que o `install_me` do `.exe` faz;
     - os links de "Adicionar/Remover programas" apontam para o código-fonte (oferta da AGPL);
  4. `nuget restore` e `msbuild` (o NuGet é baixado para `<Raiz>\ferramentas\nuget`, e o WiX vem pelo NuGet), assina o `.msi` e devolve o `res/msi` ao original (`git checkout` + `git clean`).
- **O que já vem do projeto do RustDesk:**
  - serviço do Windows criado e iniciado;
  - regras de firewall;
  - atalhos no Menu Iniciar e na Área de Trabalho, mais o da bandeja na inicialização;
  - **nenhuma impressora**: ela só é instalada com `PRINTER=1`.
- **`9_publicar.ps1`:** põe o MSI na pasta da versão e no `versao.json`, na chave `<nome>-msi`, com o SHA-256. O `configuracao.ps1` ganhou o tipo `msi` no `Nome-Arquivo`.
- **Instalação pelo ERP, sem tela:** `msiexec /i suporte-vX.Y.Z-client-x64.msi /qn`. Só aparece o pedido de administrador do Windows.
- **Limitações:**
  - o MSI **se recusa a instalar** onde o Cliente foi instalado pelo `.exe` (`BlockSelfInstalledApp` do RustDesk). Nessas máquinas, desinstale o Cliente uma vez antes;
  - em "Adicionar/Remover programas" e nos atalhos, o nome aparece sem espaços (`SuporteVetorSistemas`), porque o projeto usa o nome interno;
  - o Console Técnico continua só em `.exe`. O MSI do RustDesk ainda não trata programas "só acessa".

## 1.1.1 (em teste, número interno 16)

### Técnico e Console Técnico: acesso só pelo ID que o cliente informa

O técnico não escolhe mais computador numa lista. O cliente chama o suporte e informa o ID, e o técnico digita o ID na barra de cima e clica em Conectar.

- A lateral **perdeu as seções Clientes, Recentes e Favoritos**. Ficaram Configurações, o cartão da conta com o status dos servidores e a versão.
- A barra de cima ficou com o campo do ID, o Conectar, os outros modos (transferir arquivo, terminal etc.) e o estilo visual. **Saíram** a busca, a ordenação, a troca entre cartões e lista e o botão de atualizar a lista.
- A área central mostra a orientação "Acesso a pedido do cliente", em 3 passos, no lugar da lista de computadores.
- Tudo depende da constante `cadenaSoPorId` em `scripts/modelos/cadena_inicio.dart`. Com `false`, volta o visual com a lista. No `scripts/2_marca.ps1`, a área central usa o widget novo `CadenaSoId` quando a constante está ligada.
- O painel da API não mudou: empresas, apelidos e dispositivos continuam lá.

### Cliente: "só clique" travado (a senha não aparece nem é pedida)

- **Problema visto em 23/11/2026 numa máquina de cliente:**
  - a tela do Cliente mostrava a **senha**;
  - o Console **pedia a senha**;
  - a janela de aprovação aparecia mesmo assim.

  O Cliente estava em "senha **ou** clique", o modo padrão do RustDesk. Nele, **quem tem a senha entra sem o clique do cliente**.
- **Causa:** o `approve-mode = click` era um **padrão** (`default-settings`) do perfil do Cliente. O RustDesk lê as opções na ordem trava → opção gravada na máquina → padrão (`Config::get_option`/`get_or`). Uma opção já gravada nessa máquina, por uma instalação anterior ou pelas Configurações, venceu o padrão.
- **Correção:** o `approve-mode = click` virou **trava** (`override-settings`) no Cliente, em `2_marca.ps1`, na função `cadena_perfil`. Agora vale em qualquer máquina, mesmo com configuração antiga, e fica bloqueado nas Configurações > Segurança.
- **Decisão:** a senha aleatória do RustDesk **não** substitui a liberação de 10 minutos. Nesse modo, quem tem a senha entra sem clique, e a senha só muda depois de **usada** ou ao reiniciar. Um técnico com o ID e a senha poderia entrar dias depois. Ficam o **clique a cada acesso** e a **liberação por tempo**.
- **Máquinas já instaladas:** reinstale o Cliente novo por cima.

### Cliente: liberação do acesso (o ID fixo só aceita conexão com o pedido do cliente)

O ID é fixo, porque é calculado a partir do endereço MAC da placa de rede, e o técnico fica sabendo dele. Para o técnico não conseguir acessar quando quiser, o Cliente passou a **recusar qualquer pedido de conexão fora de uma liberação aberta pelo próprio cliente**. Optamos por não trocar o ID a cada atendimento: isso quebraria o painel, a auditoria e o vínculo com o ERP.

- **Regra:** sem liberação, a conexão é recusada **antes** da janela de aprovação, sem mostrar nada ao cliente. O Console mostra: *"O cliente não liberou o acesso. Peça para ele abrir o Suporte Vetor Sistemas e tente de novo."*
  - Dentro da liberação, nada muda: a janela de aprovação aparece, e o cliente clica em Aceitar.
- **Quem libera:** abrir ou focar a janela do Suporte Vetor, ou o botão **Liberar**. Vale por **10 minutos**.
  - A tela mostra **"Acesso liberado ao suporte · 9:58"** com o botão **Encerrar**, ou "Acesso fechado ao suporte" com o botão **Liberar**.
  - Depois de Encerrar, focar a janela não libera de novo: só o botão Liberar ou abrir a janela outra vez. É o widget `_CadenaLiberacao`, em `scripts/modelos/cadena_cliente.dart`.
- **Durante um atendimento:** novas conexões passam, como a transferência de arquivo aberta no meio do acesso (`AUTHED_CONNS` não vazio).
- **Fim de cada atendimento autorizado:** a liberação vai para "agora + 10 min", para reconectar ou reiniciar o computador (`on_close`).
- **Proteção:** uma liberação com prazo maior que 30 minutos é ignorada, então nem uma opção adulterada deixa o acesso aberto.
- **Onde fica:**
  - a opção `cadena-liberado-ate` (hora do fechamento, em segundos desde 1970) é gravada nas opções do **serviço** pela janela, via IPC, sem precisar de administrador. Vale para o instalado e sobrevive a um reinício dentro do prazo;
  - o portão está em `src/server/connection.rs`, logo depois da lista de IDs permitidos (`check_id_whitelist`) e **antes** da reconexão rápida ("sessão recente"), que também fica bloqueada;
  - tudo isso entra pelo `2_marca.ps1` (`cadena_liberado`, `cadena_estender_liberacao`) e só vale no Cliente (incoming-only).
- **Pendente:** um alerta na API para tentativas fora da liberação. Exige mudar o `cadena-api.patch` e instalar na Máquina B.
- O comando `--vetor-liberar`, para o ERP liberar sem abrir a janela, veio na 1.1.3.

### Instalador sem escolhas para o usuário final

- A tela de instalação, do Cliente e do Console, ficou só com o título, a frase "O Suporte Vetor Sistemas será instalado neste computador." e os botões **Cancelar** e **Instalar**.
- **Saíram:**
  - o caminho e o "Alterar Caminho": instala sempre na pasta padrão, `C:\Program Files\<nome>`;
  - as opções de atalho, que agora são **sempre criados** no Menu Iniciar e na Área de Trabalho;
  - a **impressora remota**, que **nunca** é instalada. Ela apareceria na lista de impressoras do cliente e leva documentos para o técnico;
  - o aviso e o link do acordo de licença do RustDesk;
  - o botão "Executar sem instalar".
- No `2_marca.ps1`, uma troca substitui o `build` do `install_page.dart` e fixa os argumentos da instalação em `startmenu desktopicon`.

### Cliente: sem o "Sair" duplicado

- O Cliente **instalado** mostrava, além do nosso "Sair", o "Quit" do RustDesk. Ele aparece nos cartões de ajuda quando não há outro cartão. Esse "Quit" foi escondido no Cliente (`kCadenaSairNaTela`).

### Cliente: janela de aprovação com as informações da tela principal, ao lado dela

Quando o técnico pede acesso, o Cliente mostra duas janelas: a principal e a de aprovação. No RustDesk, elas são processos separados, e o Aceitar/Cancelar só existe na de aprovação. Por isso, elas não foram fundidas: a de aprovação ficou completa e passou a abrir junto da principal.

- **Topo novo na janela de aprovação** (`scripts/modelos/cadena_cm.dart`, widget `CadenaCmMarca`): logo da marca (claro ou escuro, conforme o tema), "Seu ID" com o ID deste computador e o status "Conectado de forma segura · servidores", com a bolinha verde, laranja ou vermelha. Abaixo, continua igual: quem pede o acesso, as permissões, o aviso contra golpe e os botões.
- **Janela mais alta** para caber o topo: `kConnectionManagerWindowSizeClosedChat` e `...OpenChat` passaram de 490 para 600 de altura (`consts.dart`).
- **Abre ao lado da janela principal**, e não mais no canto superior direito da tela:
  - o `main.dart` chama `cadenaCmAoLado()` logo depois de cada `setSizeAlignment` do `showCmWindow`;
  - o Rust (`main_set_common`, chave `cadena-cm-ao-lado`) acha a janela principal pelo título, que é o nome exibido da marca, na classe `FLUTTER_RUNNER_WIN32_WINDOW`, fora do próprio processo, visível e não minimizada;
  - ele põe a aprovação à direita da principal, alinhada pelo topo e com 8 px de espaço. Se não couber, põe à esquerda, sempre dentro da área de trabalho do monitor;
  - sem a principal na tela, a aprovação fica no canto, como no RustDesk.
- **Sem o botão "Chamar Suporte no WhatsApp":** o campo `WhatsApp` da marca da Vetor, que fica fora do repositório, foi esvaziado. O telefone do suporte continua no aviso da janela de aprovação.
  - **Mac:** o build do Mac lê a marca do segredo `CADENA_MARCA_ZIP` do ambiente `vetor`. O segredo foi gravado de novo em 23/11/2026 com a marca sem o WhatsApp: a pasta da marca em `.zip`, com o `marca.psd1` na raiz, em base64. Sempre que a marca mudar, grave o segredo de novo.
- Testado em 23/11/2026 com o Cliente portátil: as duas janelas abrem lado a lado.

### Atualização manual: os programas não procuram versão nova

- **Saiu** a atualização automática própria, `cadena_atualizar` no `updater.rs`, gerado pelo `2_marca.ps1`:
  - o serviço do Cliente baixava o `versao.assinado` das releases do GitHub a cada 3 horas e se reinstalava sozinho;
  - o Console perguntava "Há uma versão nova… Atualizar agora?".
- **Ficou assim:** o `check_update` volta sem fazer nada no cliente personalizado. A verificação original do RustDesk (`api.rustdesk.com`) já era desligada pelo próprio RustDesk no cliente personalizado, inclusive no macOS.
- **Saiu** a ligação da verificação no Técnico/Console (`rendezvous_mediator.rs`), junto com o intervalo de 3 horas.
- **Saiu** a opção "Auto update" das Configurações (`scripts/modelos/cadena_outras_opcoes.dart`).
- O `CADENA_NUMERO`, número interno da compilação, continua. O `9_publicar.ps1` o usa para conferir o fonte.
- **Para atualizar um computador:** rode o instalador novo por cima.
- **Versões até a 1.1.0:** ainda têm a atualização automática pelas releases de `claudiocalixto/suportevetor`. Elas só se atualizariam se uma release com número maior fosse publicada lá, o que não é mais feito. A v1.1.0 continua publicada e é mantida.

### Publicação

- Commit e push **não publicam nada**. O `windows.yml` só roda manualmente. O `macos.yml` roda manualmente ou com push na branch `mac`, e só gera artefatos do Actions. Nenhum workflow cria release.
- Os executáveis passam a ser gerados localmente (`0_nova_versao.ps1`, ou `8_compilar_perfis.ps1` + `9_publicar.ps1 -SemCompilar`) e entregues por fora. O `-Publicar` não é mais usado.

### Outros

- Os links do código-fonte (oferta da AGPL), no rodapé do painel e no `LEIA-ME.txt` do pacote de fonte, apontam para `claudiocalixto/suportevetor-codigo`. Commit `1a5204d`.

## 1.1.0 (número interno 15), 14/11/2026

Versão em produção quando os repositórios foram transferidos para `claudiocalixto`.
