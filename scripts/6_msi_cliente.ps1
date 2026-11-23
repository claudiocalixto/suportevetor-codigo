# MSI do Cliente (Vetor, 2026-11-23). O provedor onde os instaladores ficam para o ERP baixar nao aceita .exe, entao o
# Cliente tambem sai como suporte-v<versao>-client-x64.msi. Usa o projeto WiX v4 do proprio RustDesk (res/msi) sobre a
# pasta compilada do Cliente, com tres mudancas nossas:
#   - sem o assistente (e o acordo de licenca do RustDesk, em ingles): instala direto, so com a barra de progresso e o
#     pedido de administrador do Windows;
#   - grava o certificado publico da marca como confiavel (Root e TrustedPublisher), como faz o install_me do .exe;
#   - os links do Adicionar/Remover Programas apontam para o codigo-fonte (AGPL), nao para o RustDesk.
# O resto ja vem do projeto: servico do Windows, firewall, atalhos no Menu Iniciar e na Area de Trabalho e nada de
# impressora (so com PRINTER=1). Pelo ERP, sem nenhuma tela: msiexec /i suporte-v<versao>-client-x64.msi /qn
# Atencao: o MSI se recusa a instalar onde o Cliente foi instalado pelo .exe (desinstale antes).
# Rode depois de compilar o Cliente (CADENA_PERFIL vazio): usa a pasta Release do Flutter. O 8_compilar_perfis o chama.
# O preprocess.py reescreve o res/msi no lugar; o script o devolve ao original no fim (git checkout + clean).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ambiente.ps1"
. "$PSScriptRoot\assinar.ps1"
$Fonte = "$Raiz\rustdesk"
$Release = "$Fonte\flutter\build\windows\x64\runner\Release"
$Msi = "$Fonte\res\msi"
$Dist = "$Raiz\msi-cliente"
$NomeApp = $Marca.NomeCliente
$Py = "$Ferramentas\python\python.exe"
$Saida = "$Entrega\$(Nome-Arquivo 'client' 'msi')"
if (-not (Test-Path "$Release\rustdesk.exe")) { throw "Compile o Cliente antes: $Release\rustdesk.exe nao existe" }

"=== Ferramentas do MSI (NuGet; o WiX vem pelo NuGet)"
$NuGet = "$Ferramentas\nuget\nuget.exe"
if (-not (Test-Path $NuGet)) {
  New-Item -ItemType Directory -Force (Split-Path $NuGet) | Out-Null
  & curl.exe -fsSL --retry 3 -o $NuGet 'https://dist.nuget.org/win-x86-commandline/v6.11.1/nuget.exe'
  if ($LASTEXITCODE -ne 0) { throw 'download do nuget' }
}
$VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$MSBuild = & $VsWhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $MSBuild) { throw 'MSBuild nao encontrado (Visual Studio 2022 Build Tools)' }

function Limpar-Msi {
  & git -C $Fonte checkout --quiet -- res/msi
  & git -C $Fonte clean -fdxq -- res/msi
}

"=== Pasta do Cliente para o MSI"
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
Copy-Item -Recurse $Release $Dist
# O MSI procura o programa pelo nome interno (o instalador .exe tambem o instala com esse nome)
Rename-Item "$Dist\rustdesk.exe" "$NomeApp.exe"
# Certificado PUBLICO da marca, gravado como confiavel pela acao CadenaCertificado* (abaixo)
if ($CertificadoB64) {
  [IO.File]::WriteAllBytes("$Dist\cadena-editor.cer", [Convert]::FromBase64String($CertificadoB64))
} else {
  'AVISO: sem o certificado da marca, o MSI nao o grava como confiavel'
}

Limpar-Msi
Push-Location $Msi
try {
  "=== preprocess.py ($NomeApp $VersaoProduto)"
  & $Py preprocess.py -d $Dist --app-name $NomeApp -v $VersaoProduto -m "$($Marca.Empresa)" -c --conn-type incoming
  if ($LASTEXITCODE -ne 0) { throw "preprocess.py saiu com $LASTEXITCODE" }

  "=== Mudancas da Vetor no projeto"
  function Mudar([string]$arquivo, [string]$de, [string]$para, [switch]$Regex) {
    # Caminho completo: o [IO.File] usa a pasta do processo, nao a do Push-Location
    $arquivo = Join-Path $Msi $arquivo
    $texto = [IO.File]::ReadAllText($arquivo, [Text.Encoding]::UTF8)
    $novo = if ($Regex) { [regex]::Replace($texto, $de, $para) } else { $texto.Replace($de, $para) }
    if ($novo -eq $texto) { throw "nao encontrado em ${arquivo}: $de" }
    [IO.File]::WriteAllText($arquivo, $novo, (New-Object Text.UTF8Encoding $true))
  }
  # Sem o assistente: sem dialogos referenciados, o Windows Installer mostra so o progresso (o aviso "outro
  # aplicativo" do assistente fica so como erro, pela BlockSelfInstalledApp da sequencia de execucao)
  Mudar 'Package\Package.wxs' '<ui:WixUI Id="UI_MyInstallDialog" InstallDirectory="INSTALLFOLDER_INNER" />' '<!-- CadenaTech: sem o assistente nem o acordo de licenca (6_msi_cliente.ps1) -->'
  Mudar 'Package\Package.wxs' '(?s)<InstallUISequence>.*?</InstallUISequence>' '<!-- CadenaTech: sem o assistente, sem o UI_AnotherAppDialog -->' -Regex
  # Certificado da marca como confiavel, como o install_me do .exe. Deferred e como sistema; falha nao aborta
  $acoes = @'
		<!-- CadenaTech: certificado da marca como confiavel (Root e Editores Confiaveis), como o install_me do .exe -->
		<CustomAction Id="CadenaCertificadoRoot" Directory="INSTALLFOLDER_INNER" ExeCommand="&quot;[System64Folder]certutil.exe&quot; -f -addstore Root &quot;[INSTALLFOLDER_INNER]cadena-editor.cer&quot;" Execute="deferred" Impersonate="no" Return="ignore" />
		<CustomAction Id="CadenaCertificadoEditor" Directory="INSTALLFOLDER_INNER" ExeCommand="&quot;[System64Folder]certutil.exe&quot; -f -addstore TrustedPublisher &quot;[INSTALLFOLDER_INNER]cadena-editor.cer&quot;" Execute="deferred" Impersonate="no" Return="ignore" />
		<InstallExecuteSequence>
			<Custom Action="CadenaCertificadoRoot" After="InstallFiles" Condition="NOT REMOVE" />
			<Custom Action="CadenaCertificadoEditor" After="CadenaCertificadoRoot" Condition="NOT REMOVE" />
'@
  Mudar 'Package\Components\RustDesk.wxs' '(?m)^\s*<InstallExecuteSequence>' $acoes.TrimEnd() -Regex
  # Adicionar/Remover Programas: links para o codigo-fonte (oferta da AGPL), nao para o RustDesk
  Mudar 'Package\Fragments\AddRemoveProperties.wxs' 'https://github.com/rustdesk/rustdesk/issues/' 'https://github.com/claudiocalixto/suportevetor-codigo'
  Mudar 'Package\Fragments\AddRemoveProperties.wxs' 'https://github.com/rustdesk/rustdesk"' 'https://github.com/claudiocalixto/suportevetor-codigo"'

  "=== nuget restore"
  & $NuGet restore msi.sln -NonInteractive -Verbosity quiet -MSBuildPath (Split-Path $MSBuild)
  if ($LASTEXITCODE -ne 0) { throw "nuget restore saiu com $LASTEXITCODE" }

  "=== msbuild"
  & $MSBuild msi.sln -nologo -v:minimal -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
  if ($LASTEXITCODE -ne 0) { throw "msbuild saiu com $LASTEXITCODE" }

  $gerado = Get-ChildItem 'Package\bin\*\Release\en-us\Package.msi' | Select-Object -First 1
  if (-not $gerado) { throw 'o msbuild nao gerou o Package.msi' }
  Copy-Item -Force $gerado.FullName $Saida
} finally {
  Pop-Location
  Limpar-Msi
}

"=== Assinatura do MSI"
Assinar-Arquivos @($Saida)
"$(Split-Path $Saida -Leaf) $([math]::Round((Get-Item $Saida).Length/1MB,1)) MB sha256=$((Get-FileHash $Saida -Algorithm SHA256).Hash)"
"=== Concluido"
