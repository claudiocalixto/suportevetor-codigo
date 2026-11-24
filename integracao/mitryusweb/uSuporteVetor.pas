unit uSuporteVetor;

{ ============================================================================
  Suporte remoto Vetor no MitryusWeb (Delphi 2007, sem componentes de terceiros)

  Fluxo de SuporteVetorAbrir:
    1. Verifica se o Cliente (SuporteVetorSistemas) está instalado e em que versão.
    2. Baixa o versao.json de SV_URL_BASE e compara com a versão instalada.
    3. Se não estiver instalado, ou se houver versão nova: baixa o MSI, confere o
       SHA-256 e instala (pede administrador uma vez, pelo UAC).
       Se o Cliente antigo foi instalado pelo .exe, desinstala antes (o MSI recusa
       instalar por cima dele).
    4. Lê o ID do computador com "SuporteVetorSistemas.exe --get-id".
    5. Libera o acesso ao suporte por 10 minutos com "--vetor-liberar", SEM abrir
       a janela do Cliente (ele fica na bandeja e não cobre a tela do ERP). Sem a
       liberação, o técnico recebe "O cliente não liberou o acesso".
       Quando o técnico conectar, aparece só a janela de aprovação (Aceitar).
       Cliente anterior à 1.1.3 (sem o comando): abre a janela, que também libera.

  No site (SV_URL_BASE) ficam, a cada versão nova, os dois arquivos da pasta
  <Entrega>\publicar\vX.Y.Z:
    - suporte-vX.Y.Z-client-x64.msi
    - versao.json   (sempre com esse nome; é ele que diz qual é a versão atual)

  Uso:
    var Id, Erro: string;
    if SuporteVetorAbrir(Id, Erro) then
      ShowMessage('Informe ao suporte o ID: ' + Id)
    else
      ShowMessage(Erro);
  ============================================================================ }

interface

uses
  Windows, Messages, SysUtils, Classes, ShellAPI, UrlMon, WinInet, Forms;

const
  // Pasta do site onde ficam o versao.json e o MSI (termina com "/")
  SV_URL_BASE      = 'https://www.mitryusweb.com.br/SUPORTE/';
  SV_ARQ_VERSAO    = 'versao.json';

  // Nome interno do Cliente (marca Vetor). Não mude.
  SV_NOME_APP      = 'SuporteVetorSistemas';
  // Chave do MSI dentro do versao.json
  SV_CHAVE_MSI     = 'suportevetorsistemas-msi';
  // UpgradeCode do MSI: uuid5(OID, 'SuporteVetorSistemas.exe'), gerado pelo preprocess.py do RustDesk.
  // É o mesmo em todas as versões; é por ele que o Windows sabe qual versão está instalada.
  SV_UPGRADE_CODE  = '{662564EC-9C68-51A1-9469-01C410A95CC9}';

  // /passive mostra só a barra de progresso; troque por /qn para não mostrar nada
  SV_MSI_MODO      = '/passive';

type
  // Opcional: recebe mensagens de andamento para mostrar ao usuário (ex.: num TLabel)
  TSuporteVetorEtapa = procedure(const AMensagem: string) of object;

function SuporteVetorAbrir(out AId: string; out AErro: string;
  AEtapa: TSuporteVetorEtapa = nil): Boolean;

// Funções avulsas, se quiser montar o fluxo de outro jeito
function SVWindows64: Boolean;
function SVExeInstalado: string;          // caminho do exe, ou '' se não instalado
function SVVersaoInstalada: string;       // versão do MSI instalado (ex.: '1.1.2.0'), ou ''
function SVVersaoInstaladaPeloExe: string; // versão de um Cliente antigo instalado pelo .exe, ou ''
function SVObterId(const AExe: string): string;
function SVLiberar(const AExe: string): Boolean;      // libera 10 min sem abrir janela
function SVAbrirCliente(const AExe: string): Boolean; // abre a janela (também libera)
function SVCompararVersoes(const A, B: string): Integer; // 1 se A > B, -1 se A < B, 0 se iguais

implementation

const
  SV_KEY_WOW64_64KEY      = $0100;  // ler o registro de 64 bits a partir do programa de 32 bits
  SV_HANDLE_FLAG_INHERIT  = $0001;
  SV_CREATE_NO_WINDOW     = $08000000;
  SV_PROV_RSA_AES         = 24;
  SV_CALG_SHA_256         = $0000800C;
  SV_HP_HASHVAL           = $0002;
  SV_CRYPT_VERIFYCONTEXT  = $F0000000;
  SV_ERROR_CANCELLED      = 1223;   // o usuário recusou o pedido de administrador
  SV_CHAVE_DESINSTALAR    = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + SV_NOME_APP;

var
  GOcupado: Boolean = False;

{ --- APIs que o Delphi 2007 não declara ------------------------------------ }

function MsiEnumRelatedProductsA(lpUpgradeCode: PChar; dwReserved: DWORD;
  iProductIndex: DWORD; lpProductBuf: PChar): UINT; stdcall; external 'msi.dll';
function MsiGetProductInfoA(szProduct, szAttribute: PChar; lpValueBuf: PChar;
  var pcchValueBuf: DWORD): UINT; stdcall; external 'msi.dll';

function CryptAcquireContextA(var phProv: THandle; pszContainer, pszProvider: PChar;
  dwProvType, dwFlags: DWORD): BOOL; stdcall; external advapi32;
function CryptCreateHash(hProv: THandle; Algid: DWORD; hKey: THandle; dwFlags: DWORD;
  var phHash: THandle): BOOL; stdcall; external advapi32;
function CryptHashData(hHash: THandle; pbData: Pointer; dwDataLen, dwFlags: DWORD): BOOL;
  stdcall; external advapi32;
function CryptGetHashParam(hHash: THandle; dwParam: DWORD; pbData: Pointer;
  var pdwDataLen: DWORD; dwFlags: DWORD): BOOL; stdcall; external advapi32;
function CryptDestroyHash(hHash: THandle): BOOL; stdcall; external advapi32;
function CryptReleaseContext(hProv: THandle; dwFlags: DWORD): BOOL; stdcall; external advapi32;

{ --- Utilitários ------------------------------------------------------------ }

procedure Esperar(AMs: Cardinal);
var
  Inicio: Cardinal;
begin
  Inicio := GetTickCount;
  while GetTickCount - Inicio < AMs do
  begin
    Application.ProcessMessages;
    Sleep(50);
  end;
end;

function LerRegistro(ARaiz: HKEY; const AChave, AValor: string): string;
var
  K: HKEY;
  Tipo, Tam: DWORD;
  Buf: array[0..2047] of Char;
begin
  Result := '';
  if RegOpenKeyEx(ARaiz, PChar(AChave), 0, KEY_READ or SV_KEY_WOW64_64KEY, K) <> ERROR_SUCCESS then
    Exit;
  try
    FillChar(Buf, SizeOf(Buf), 0);
    Tam := SizeOf(Buf) - 1;
    if (RegQueryValueEx(K, PChar(AValor), nil, @Tipo, PByte(@Buf[0]), @Tam) = ERROR_SUCCESS) and
       ((Tipo = REG_SZ) or (Tipo = REG_EXPAND_SZ)) then
      Result := PChar(@Buf[0]);
  finally
    RegCloseKey(K);
  end;
end;

function PastaTemp: string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  GetTempPath(MAX_PATH, Buf);
  Result := IncludeTrailingPathDelimiter(PChar(@Buf[0])) + 'SuporteVetor\';
  ForceDirectories(Result);
end;

function Baixar(const AUrl, ADestino: string): Boolean;
begin
  DeleteUrlCacheEntry(PChar(AUrl));   // não usar cópia antiga do cache do Internet Explorer
  if FileExists(ADestino) then
    DeleteFile(ADestino);
  Result := (URLDownloadToFile(nil, PChar(AUrl), PChar(ADestino), 0, nil) = S_OK) and
            FileExists(ADestino);
end;

function LerArquivoTexto(const AArquivo: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(AArquivo);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

// Leitor mínimo de JSON: devolve o valor (texto entre aspas ou número) da primeira
// chave AChave encontrada a partir da posição AInicio. Basta para o versao.json.
function JsonValor(const AJson, AChave: string; AInicio: Integer): string;
var
  S: string;
  P, I: Integer;
begin
  Result := '';
  S := Copy(AJson, AInicio, MaxInt);
  P := Pos('"' + AChave + '"', S);
  if P = 0 then
    Exit;
  I := P + Length(AChave) + 2;
  while (I <= Length(S)) and (S[I] in [' ', #9, #13, #10, ':']) do
    Inc(I);
  if (I <= Length(S)) and (S[I] = '"') then
  begin
    Inc(I);
    while (I <= Length(S)) and (S[I] <> '"') do
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end
  else
    while (I <= Length(S)) and (S[I] in ['0'..'9', '.']) do
    begin
      Result := Result + S[I];
      Inc(I);
    end;
end;

function Sha256Arquivo(const AArquivo: string): string;
var
  Prov, Hash: THandle;
  F: TFileStream;
  Buf: array[0..65535] of Byte;
  Lido: Integer;
  Dig: array[0..31] of Byte;
  Tam: DWORD;
  I: Integer;
begin
  Result := '';
  if not CryptAcquireContextA(Prov, nil, nil, SV_PROV_RSA_AES, SV_CRYPT_VERIFYCONTEXT) then
    Exit;
  try
    if not CryptCreateHash(Prov, SV_CALG_SHA_256, 0, 0, Hash) then
      Exit;
    try
      F := TFileStream.Create(AArquivo, fmOpenRead or fmShareDenyWrite);
      try
        repeat
          Lido := F.Read(Buf, SizeOf(Buf));
          if (Lido > 0) and not CryptHashData(Hash, @Buf[0], Lido, 0) then
            Exit;
        until Lido <= 0;
      finally
        F.Free;
      end;
      Tam := SizeOf(Dig);
      if not CryptGetHashParam(Hash, SV_HP_HASHVAL, @Dig[0], Tam, 0) then
        Exit;
      for I := 0 to 31 do
        Result := Result + LowerCase(IntToHex(Dig[I], 2));
    finally
      CryptDestroyHash(Hash);
    end;
  finally
    CryptReleaseContext(Prov, 0);
  end;
end;

// Roda um programa como administrador (pedido do UAC) e espera terminar, sem travar a tela
function ExecutarElevado(const AArquivo, AParametros: string; out ACodigo: DWORD): Boolean;
var
  SEI: TShellExecuteInfo;
begin
  ACodigo := DWORD(-1);
  FillChar(SEI, SizeOf(SEI), 0);
  SEI.cbSize := SizeOf(SEI);
  SEI.fMask := SEE_MASK_NOCLOSEPROCESS;
  SEI.Wnd := Application.Handle;
  SEI.lpVerb := 'runas';
  SEI.lpFile := PChar(AArquivo);
  SEI.lpParameters := PChar(AParametros);
  SEI.nShow := SW_SHOWNORMAL;
  Result := ShellExecuteEx(@SEI);
  if not Result then
  begin
    ACodigo := GetLastError;
    Exit;
  end;
  if SEI.hProcess = 0 then
    Exit;
  try
    while MsgWaitForMultipleObjects(1, SEI.hProcess, False, INFINITE, QS_ALLINPUT) = WAIT_OBJECT_0 + 1 do
      Application.ProcessMessages;
    GetExitCodeProcess(SEI.hProcess, ACodigo);
  finally
    CloseHandle(SEI.hProcess);
  end;
end;

{ --- Funções públicas ------------------------------------------------------- }

function SVWindows64: Boolean;
type
  TIsWow64Process = function(hProcess: THandle; var Wow64Process: BOOL): BOOL; stdcall;
var
  F: TIsWow64Process;
  B: BOOL;
begin
  // O programa em Delphi 2007 é 32 bits: rodando no WOW64 = Windows de 64 bits
  Result := False;
  @F := GetProcAddress(GetModuleHandle('kernel32.dll'), 'IsWow64Process');
  B := False;
  if Assigned(F) and F(GetCurrentProcess, B) then
    Result := B;
end;

function SVExeInstalado: string;
var
  Pasta: string;
begin
  Result := '';
  // Gravado pelo MSI
  Pasta := LerRegistro(HKEY_CLASSES_ROOT, '.' + LowerCase(SV_NOME_APP), 'INSTALLFOLDER');
  // Pasta padrão (também a do instalador .exe antigo). ProgramW6432 = "C:\Program Files" de 64 bits
  if Pasta = '' then
    Pasta := GetEnvironmentVariable('ProgramW6432') + '\' + SV_NOME_APP;
  if Pasta = '' then
    Exit;
  Pasta := IncludeTrailingPathDelimiter(Pasta);
  if FileExists(Pasta + SV_NOME_APP + '.exe') then
    Result := Pasta + SV_NOME_APP + '.exe';
end;

function SVVersaoInstalada: string;
var
  Produto: array[0..38] of Char;
  Buf: array[0..63] of Char;
  Tam: DWORD;
begin
  Result := '';
  FillChar(Produto, SizeOf(Produto), 0);
  if MsiEnumRelatedProductsA(SV_UPGRADE_CODE, 0, 0, Produto) <> ERROR_SUCCESS then
    Exit;
  FillChar(Buf, SizeOf(Buf), 0);
  Tam := Length(Buf);
  if MsiGetProductInfoA(Produto, 'VersionString', Buf, Tam) = ERROR_SUCCESS then
    Result := PChar(@Buf[0]);
end;

function SVVersaoInstaladaPeloExe: string;
begin
  // O instalador .exe grava a chave de desinstalação com o nome interno; o MSI não a usa
  Result := '';
  if SVVersaoInstalada <> '' then
    Exit;
  if LerRegistro(HKEY_LOCAL_MACHINE, SV_CHAVE_DESINSTALAR, 'UninstallString') = '' then
    Exit;
  Result := LerRegistro(HKEY_LOCAL_MACHINE, SV_CHAVE_DESINSTALAR, 'DisplayVersion');
  if Result = '' then
    Result := '0';
end;

function SVCompararVersoes(const A, B: string): Integer;

  function Parte(var S: string): Integer;
  var
    P: Integer;
  begin
    P := Pos('.', S);
    if P = 0 then
      P := Length(S) + 1;
    Result := StrToIntDef(Trim(Copy(S, 1, P - 1)), 0);
    Delete(S, 1, P);
  end;

var
  X, Y: string;
  I, PA, PB: Integer;
begin
  // '1.1.2' e '1.1.2.0' são iguais (o MSI acrescenta o quarto número)
  Result := 0;
  X := A;
  Y := B;
  for I := 1 to 4 do
  begin
    PA := Parte(X);
    PB := Parte(Y);
    if PA <> PB then
    begin
      if PA > PB then
        Result := 1
      else
        Result := -1;
      Exit;
    end;
  end;
end;

// Roda o exe escondido (sem janela) com os parâmetros e devolve o que ele escreveu no stdout
function ExecutarOculto(const AExe, AParametros: string): string;
var
  SA: TSecurityAttributes;
  Leitura, Escrita: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  Buf: array[0..1023] of Char;
  Lido, Disp: DWORD;
  Saida, Cmd, Parte: string;
begin
  Result := '';
  if (AExe = '') or not FileExists(AExe) then
    Exit;

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;
  if not CreatePipe(Leitura, Escrita, @SA, 0) then
    Exit;
  Saida := '';
  try
    SetHandleInformation(Leitura, SV_HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    SI.hStdOutput := Escrita;
    SI.hStdError := Escrita;
    Cmd := '"' + AExe + '" ' + AParametros;
    UniqueString(Cmd);
    if not CreateProcess(nil, PChar(Cmd), nil, nil, True, SV_CREATE_NO_WINDOW, nil,
      PChar(ExtractFilePath(AExe)), SI, PI) then
      Exit;
    CloseHandle(Escrita);
    Escrita := 0;
    try
      // A resposta é curta e cabe no buffer do pipe: espera o processo terminar e depois lê
      if WaitForSingleObject(PI.hProcess, 20000) = WAIT_TIMEOUT then
        TerminateProcess(PI.hProcess, 1);
      while PeekNamedPipe(Leitura, nil, 0, nil, @Disp, nil) and (Disp > 0) do
      begin
        Lido := 0;
        if not ReadFile(Leitura, Buf, SizeOf(Buf), Lido, nil) or (Lido = 0) then
          Break;
        SetString(Parte, PChar(@Buf[0]), Lido);
        Saida := Saida + Parte;
      end;
    finally
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
    end;
  finally
    CloseHandle(Leitura);
    if Escrita <> 0 then
      CloseHandle(Escrita);
  end;
  Result := Saida;
end;

// Última linha da saída que tem só dígitos, com AMin a AMax caracteres ('' se não houver)
function LinhaNumerica(const ASaida: string; AMin, AMax: Integer): string;
var
  L: TStringList;
  Linha: string;
  I, J: Integer;
  SoDigitos: Boolean;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := ASaida;
    for I := L.Count - 1 downto 0 do
    begin
      Linha := Trim(L[I]);
      SoDigitos := (Length(Linha) >= AMin) and (Length(Linha) <= AMax);
      for J := 1 to Length(Linha) do
        if not (Linha[J] in ['0'..'9']) then
          SoDigitos := False;
      if SoDigitos then
      begin
        Result := Linha;
        Break;
      end;
    end;
  finally
    L.Free;
  end;
end;

function SVObterId(const AExe: string): string;
begin
  // O ID tem 9 ou 10 dígitos, normalmente
  Result := LinhaNumerica(ExecutarOculto(AExe, '--get-id'), 6, 12);
end;

function SVLiberar(const AExe: string): Boolean;
begin
  // Libera o acesso ao suporte por 10 minutos SEM abrir a janela do Cliente.
  // O Cliente responde com a hora do fechamento (segundos desde 1970); sem resposta, não liberou
  // (Cliente anterior à 1.1.3, que não tem o comando, ou serviço parado).
  Result := LinhaNumerica(ExecutarOculto(AExe, '--vetor-liberar'), 9, 12) <> '';
end;

function SVAbrirCliente(const AExe: string): Boolean;
begin
  // Abrir (ou trazer para a frente) a janela também libera o acesso por 10 minutos,
  // mas cobre a tela do ERP. Use só se o SVLiberar não funcionar.
  Result := ShellExecute(Application.Handle, 'open', PChar(AExe), nil,
    PChar(ExtractFilePath(AExe)), SW_SHOWNORMAL) > 32;
end;

{ --- Fluxo completo --------------------------------------------------------- }

function SuporteVetorAbrir(out AId: string; out AErro: string;
  AEtapa: TSuporteVetorEtapa = nil): Boolean;

  procedure Etapa(const S: string);
  begin
    if Assigned(AEtapa) then
      AEtapa(S);
    Application.ProcessMessages;
  end;

var
  Exe, VerMsi, VerExe, VerAtual, VerWeb, Json, Arquivo, Hash, Pasta, Msi, Log: string;
  Codigo: DWORD;
  P, I: Integer;
  Precisa: Boolean;
begin
  Result := False;
  AId := '';
  AErro := '';
  if GOcupado then
  begin
    AErro := 'O Suporte remoto já está sendo preparado. Aguarde.';
    Exit;
  end;
  GOcupado := True;
  try
    if not SVWindows64 then
    begin
      AErro := 'Este computador tem Windows de 32 bits. Peça ao suporte o instalador de 32 bits.';
      Exit;
    end;

    { 1. O que está instalado }
    Etapa('Verificando o Suporte remoto...');
    Exe := SVExeInstalado;
    VerMsi := SVVersaoInstalada;
    VerExe := SVVersaoInstaladaPeloExe;
    if VerMsi <> '' then
      VerAtual := VerMsi
    else
      VerAtual := VerExe;
    if Exe = '' then
      VerAtual := '';   // registro sem o programa: instala de novo

    { 2. Versão publicada no site }
    VerWeb := '';
    Arquivo := '';
    Hash := '';
    Pasta := PastaTemp;
    Etapa('Procurando versão nova...');
    // O "?t=" evita receber um versao.json antigo de algum cache no caminho
    if Baixar(SV_URL_BASE + SV_ARQ_VERSAO + '?t=' + IntToStr(GetTickCount), Pasta + SV_ARQ_VERSAO) then
    begin
      Json := LerArquivoTexto(Pasta + SV_ARQ_VERSAO);
      VerWeb := JsonValor(Json, 'versao', 1);
      P := Pos('"' + SV_CHAVE_MSI + '"', Json);
      if P > 0 then
      begin
        Arquivo := JsonValor(Json, 'arquivo', P);
        Hash := JsonValor(Json, 'sha256', P);
      end;
    end;

    { 3. Instalar ou atualizar }
    Precisa := (VerAtual = '') or
               ((VerWeb <> '') and (SVCompararVersoes(VerWeb, VerAtual) > 0));
    if Precisa then
    begin
      if (VerWeb = '') or (Arquivo = '') or (Hash = '') then
      begin
        if Exe = '' then
        begin
          AErro := 'Não foi possível consultar a página do Suporte remoto (' + SV_URL_BASE +
                   '). Verifique a internet e tente de novo.';
          Exit;
        end;
        // Sem acesso ao site, mas já instalado: segue com a versão que está aí
      end
      else
      begin
        Etapa('Baixando o Suporte remoto ' + VerWeb + '...');
        Msi := Pasta + Arquivo;
        if not Baixar(SV_URL_BASE + Arquivo, Msi) then
        begin
          if Exe = '' then
          begin
            AErro := 'Não foi possível baixar ' + SV_URL_BASE + Arquivo;
            Exit;
          end;
        end
        else if not SameText(Sha256Arquivo(Msi), Hash) then
        begin
          DeleteFile(Msi);
          if Exe = '' then
          begin
            AErro := 'O arquivo baixado do Suporte remoto está corrompido ou foi alterado ' +
                     '(SHA-256 não confere). Tente de novo mais tarde.';
            Exit;
          end;
        end
        else
        begin
          // O MSI recusa instalar por cima do Cliente instalado pelo .exe: desinstala antes
          if (VerExe <> '') and (Exe <> '') then
          begin
            Etapa('Removendo a versão antiga do Suporte remoto...');
            ExecutarElevado(Exe, '--uninstall', Codigo);
            for I := 1 to 30 do
            begin
              if LerRegistro(HKEY_LOCAL_MACHINE, SV_CHAVE_DESINSTALAR, 'UninstallString') = '' then
                Break;
              Esperar(1000);
            end;
          end;

          Etapa('Instalando o Suporte remoto ' + VerWeb + '...');
          Log := Pasta + 'instalacao.log';
          if not ExecutarElevado('msiexec.exe',
            '/i "' + Msi + '" ' + SV_MSI_MODO + ' /norestart /l*v "' + Log + '"', Codigo) then
          begin
            if Codigo = SV_ERROR_CANCELLED then
              AErro := 'A instalação do Suporte remoto precisa da permissão de administrador.'
            else
              AErro := 'Não foi possível iniciar a instalação (erro ' + IntToStr(Codigo) + ').';
          end
          else if not ((Codigo = 0) or (Codigo = 3010) or (Codigo = 1641)) then
            AErro := 'A instalação do Suporte remoto falhou (código ' + IntToStr(Codigo) +
                     '). Detalhes em ' + Log;

          Exe := SVExeInstalado;
          if Exe = '' then
          begin
            if AErro = '' then
              AErro := 'O Suporte remoto não foi encontrado depois da instalação.';
            Exit;
          end;
          AErro := '';  // falhou a atualização, mas a versão anterior continua lá
          Esperar(3000); // o serviço do Cliente sobe logo depois da instalação
        end;
      end;
    end;

    if Exe = '' then
    begin
      AErro := 'O Suporte remoto não está instalado.';
      Exit;
    end;

    { 4. ID do computador (tenta algumas vezes: o serviço pode estar subindo) }
    Etapa('Lendo o ID deste computador...');
    for I := 1 to 6 do
    begin
      AId := SVObterId(Exe);
      if AId <> '' then
        Break;
      Esperar(2000);
    end;

    { 5. Libera o acesso por 10 minutos sem abrir a janela (o Cliente fica na bandeja).
         Cliente antigo, sem o --vetor-liberar: abre a janela, que também libera. }
    Etapa('Liberando o acesso ao suporte...');
    if not SVLiberar(Exe) then
      if not SVAbrirCliente(Exe) then
      begin
        AErro := 'Não foi possível liberar o acesso nem abrir ' + Exe;
        Exit;
      end;

    if AId = '' then
    begin
      AErro := 'O Suporte remoto foi aberto, mas não foi possível ler o ID. ' +
               'Informe ao suporte o ID que aparece na tela.';
      Exit;
    end;
    Result := True;
  finally
    GOcupado := False;
  end;
end;

end.
