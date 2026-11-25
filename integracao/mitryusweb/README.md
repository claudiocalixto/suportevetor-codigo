# Integração com o MitryusWeb (Delphi 2007)

A unit [`LibSuporteVetor.pas`](LibSuporteVetor.pas) é o botão "Suporte remoto" do MitryusWeb: instala ou atualiza o Cliente, lê o ID do computador e libera o acesso ao suporte, tudo sem cobrir a tela do ERP. Não usa componentes de terceiros, só a API do Windows: `msi.dll`, CryptoAPI, `urlmon` e `ShellExecuteEx`.

> **Codificação:** no repositório o arquivo fica em UTF-8. O `.gitattributes` (`working-tree-encoding=CP1252`) faz o checkout em **ANSI (Windows-1252)**, que é o que o Delphi 2007 lê. Copie o arquivo do checkout, e não do navegador do GitHub, senão os acentos das mensagens saem errados.

## Uso

```pascal
uses LibSuporteVetor;

procedure TFrmPrincipal.BtnSuporteClick(Sender: TObject);
var
  Id, Erro: string;
begin
  if fSuporteVetorAbrir(Id, Erro) then
    ShowMessage('Informe ao suporte o ID deste computador: ' + Id)
  else
    ShowMessage(Erro);
end;
```

O terceiro parâmetro (opcional) recebe as mensagens de andamento ("Baixando…", "Instalando…") para mostrar num `TLabel`, por exemplo.

## O que o `fSuporteVetorAbrir` faz

| Passo | Como |
|---|---|
| 1. Está instalado? Em que versão? | `MsiEnumRelatedProducts` pelo **UpgradeCode** fixo do MSI (`{662564EC-9C68-51A1-9469-01C410A95CC9}`, igual em todas as versões) e `MsiGetProductInfo(VersionString)`. A pasta vem de `HKCR\.suportevetorsistemas\INSTALLFOLDER` |
| 2. Tem versão nova? | Baixa `versao.json` de `SV_URL_BASE` e compara o campo `versao` com o instalado. `1.1.2` = `1.1.2.0`, porque o MSI acrescenta o quarto número |
| 3. Instalar / atualizar | Baixa o arquivo de `suportevetorsistemas-msi.arquivo`, confere o `sha256` e roda `msiexec /i … /passive /norestart` como administrador. O Windows pede o UAC uma vez. O `MajorUpgrade` do MSI troca a versão antiga |
| 3a. Cliente antigo, do `.exe` | O MSI se recusa a instalar por cima (`BlockSelfInstalledApp`). A unit roda `SuporteVetorSistemas.exe --uninstall` como administrador antes, o que gera um segundo UAC |
| 4. ID do computador | `SuporteVetorSistemas.exe --get-id`, escondido, lendo o stdout. Não precisa de administrador. Tenta até 6 vezes, porque logo depois da instalação o serviço ainda está subindo |
| 5. Liberar o acesso | `SuporteVetorSistemas.exe --vetor-liberar`, escondido: libera por **10 minutos sem abrir a janela**. O Cliente fica na bandeja. Quando o técnico conecta, aparece só a janela de aprovação, com o botão Aceitar. Num Cliente anterior à 1.1.3, que não tem esse comando, a unit abre a janela, que também libera |

Sem acesso ao site, mas com o Cliente instalado, a unit segue com a versão que está instalada. Se a atualização falhar, ou o usuário recusar o UAC, ela também segue com a versão anterior.

## O que vai no site

Em `SV_URL_BASE` (hoje `https://www.mitryusweb.com.br/MITRYUSWEB/SUPORTE/`), a cada versão nova, suba **os dois** arquivos de `<Entrega>\publicar\vX.Y.Z\`:

- `suporte-vX.Y.Z-client-x64.msi`;
- `versao.json`, **sempre com esse nome**. É ele que diz qual é a versão atual e o SHA-256 do MSI.

Suba primeiro o `.msi` e depois o `versao.json`. Na ordem inversa, alguém pode ler a versão nova antes de o arquivo existir no site.

## Limitações

- Só Windows de 64 bits: não há MSI de 32 bits. Num Windows de 32 bits, a unit mostra uma mensagem e para.
- Windows 7 sem atualizações pode não baixar por HTTPS, porque falta o TLS 1.2 no sistema.
- O nome em "Adicionar/Remover programas" aparece sem espaços (`SuporteVetorSistemas`). É uma limitação do MSI.
- A troca do Cliente instalado pelo `.exe` para o MSI (passo 3a) precisa ser testada numa VM antes de ir para os clientes.
