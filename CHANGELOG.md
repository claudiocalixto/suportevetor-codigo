# Mudanças

## 1.1.1 (em teste, número interno 16)

### Técnico e Console Técnico: acesso só pelo ID que o cliente informa

O técnico não escolhe mais computador numa lista. O cliente chama o suporte e informa o ID, e o técnico digita o ID na barra de cima e clica em Conectar.

- A lateral **perdeu as seções Clientes, Recentes e Favoritos**. Ficaram Configurações, o cartão da conta com o status dos servidores e a versão.
- A barra de cima ficou com o campo do ID, o Conectar, os outros modos (transferir arquivo, terminal etc.) e o estilo visual. **Saíram** a busca, a ordenação, a troca entre cartões e lista e o botão de atualizar a lista.
- A área central mostra a orientação "Acesso a pedido do cliente", em 3 passos, no lugar da lista de computadores.
- Tudo depende da constante `cadenaSoPorId` em `scripts/modelos/cadena_inicio.dart`. Com `false`, volta o visual com a lista. No `scripts/2_marca.ps1`, a área central usa o widget novo `CadenaSoId` quando a constante está ligada.
- O painel da API não mudou: empresas, apelidos e dispositivos continuam lá.

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
  - **Mac:** o build do Mac lê a marca do segredo `CADENA_MARCA_ZIP` do ambiente `vetor`, que ainda tem o WhatsApp. Atualize o segredo antes de compilar o Mac.
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
