# Aplica a marca, os servidores e as chaves no codigo do RustDesk ($Raiz\rustdesk). Pode ser repetido: comeca
# sempre do codigo original da tag. A marca vem de marcas\<nome> (marca.psd1 + SVGs) e os servidores, as chaves
# e as pastas, do config.local.psd1 ou de variaveis de ambiente (ver configuracao.ps1).
# Compilar com CADENA_PERFIL=tecnico gera o Tecnico (so acessa); sem a variavel, o Cliente (so recebe acesso).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\configuracao.ps1"
$Fonte = "$Raiz\rustdesk"
$Saida = "$Raiz\marca-gerada"
New-Item -ItemType Directory -Force $Saida | Out-Null
Add-Type -AssemblyName System.Drawing

# Nome interno sem espacos (pastas, servico, .exe, pipes): o RustDesk usa o nome sem aspas em "sc" e "taskkill".
# Na tela, nos atalhos e em Programas instalados aparece o nome com espacos (cadena_nome_exibido / cadenaNomeExibido)
$NomeApp = $Marca.NomeCliente
$NomeTecnico = $Marca.NomeTecnico
$NomeExibido = $Marca.ExibidoCliente
$NomeExibidoTecnico = $Marca.ExibidoTecnico
# Console Tecnico (CADENA_PERFIL=console): o Tecnico com os acessos em abas na janela principal. Nome proprio, entao
# instala e guarda configuracao ao lado do Tecnico, sem mexer nele
$NomeConsole = if ($Marca.NomeConsole) { $Marca.NomeConsole } else { "Console$NomeTecnico" }
$NomeExibidoConsole = if ($Marca.ExibidoConsole) { $Marca.ExibidoConsole } else { "Console $NomeExibidoTecnico" }
$Empresa = $Marca.Empresa
$Prefixo = $Marca.Prefixo
$Descricao = "$NomeExibido - Acesso Remoto"
$Direitos = "$Empresa. Baseado no RustDesk, (c) Purslane Tech Pte. Ltd., licenca AGPL-3.0."
$Site = $Marca.Site.TrimEnd('/') + '/'
$SiteCurto = ($Site -replace '^https?://', '').TrimEnd('/')
foreach ($n in $NomeApp, $NomeTecnico, $NomeConsole, $Prefixo) {
  if ($n -notmatch '^[A-Za-z0-9]+$') { throw "Nome interno e prefixo da marca so podem ter letras e numeros: $n" }
}
# Servidores (configuracao.ps1): o 1 vai como servidor do RustDesk; o 2 e opcional
if (-not $Srv1.Endereco -or -not $Srv1.Chave) { throw 'Informe o servidor 1 e a chave dele (Servidor1 no config.local.psd1 ou CADENA_SERVIDOR1/CADENA_CHAVE1)' }
$Servidor, $Chave, $Servidor2, $Chave2 = $Srv1.Endereco, $Srv1.Chave, "$($Srv2.Endereco)", "$($Srv2.Chave)"
"Marca: $NomeExibido ($PastaMarca)"
"Servidor 1: $Servidor ($($Srv1.Nome))  Servidor 2: $(if ($Servidor2) { "$Servidor2 ($($Srv2.Nome))" } else { 'nenhum' })"

# Cores da marca: '#1D5FC8' -> '1D5FC8' (Dart: Color(0xFF1D5FC8)) e '255, 29, 95, 200' (Color.fromARGB)
function Hex([string]$cor) { return $cor.TrimStart('#').ToUpper() }
function Argb([string]$cor) {
  $h = Hex $cor
  return '255, {0}, {1}, {2}' -f [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
}
# Texto da marca dentro de codigo: aspas simples do Dart e aspas duplas do Rust
function Para-Dart([string]$s) { return $s.Replace('\', '\\').Replace("'", "\'").Replace('$', '\$') }
function Para-Rust([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }
# Texto para string da interface antiga (Sciter): o Sciter le o HTML embutido como Latin1, entao os acentos vao
# como \uXXXX (so ASCII no arquivo) e chegam certos na tela
function Para-Tis([string]$s) {
  $sb = New-Object Text.StringBuilder
  foreach ($c in (Para-Rust $s).ToCharArray()) {
    if ([int]$c -lt 128) { [void]$sb.Append($c) } else { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) }
  }
  return $sb.ToString()
}

# Comeca sempre do codigo original da tag: assim a troca de servidor (ou de qualquer texto) nao esbarra
# no que a execucao anterior ja trocou. Os arquivos gerados fora do git (ponte Flutter/Rust) ficam
& git -C "$Fonte\libs\hbb_common" checkout --quiet .
& git -C $Fonte checkout --quiet -- . ':!libs/hbb_common'
# Modulo de FTP de execucoes anteriores (arquivo novo: o checkout nao o apaga; vetor_ftp.rs e o nome antigo)
foreach ($novo in 'src\cadena_ftp.rs', 'src\vetor_ftp.rs') {
  if (Test-Path "$Fonte\$novo") {
    & git -C $Fonte rm --cached --quiet --ignore-unmatch ($novo.Replace('\', '/'))
    Remove-Item -Force "$Fonte\$novo"
  }
}

# --- Imagens: o Edge (headless) transforma os SVGs da marca em PNG; o resto e reduzido daqui ---
$Edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path $Edge)) { $Edge = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }
function Render-Svg([string]$svg, [int]$largura, [int]$altura, [string]$destino) {
  $html = "$Saida\render.html"
  $png = "$Saida\render.png"
  $url = 'file:///' + (Resolve-Path $svg).Path.Replace('\', '/')
  $pagina = "<!doctype html><html><body style=`"margin:0;background:transparent;overflow:hidden`"><img src=`"$url`" style=`"width:${largura}px;height:${altura}px;display:block`"></body></html>"
  [IO.File]::WriteAllText($html, $pagina)
  if (Test-Path $png) { Remove-Item $png }
  $argumentos = @('--headless=new', '--disable-gpu', "--user-data-dir=$Saida\perfil-edge", '--hide-scrollbars',
    '--default-background-color=00000000', "--window-size=$largura,$altura", "--screenshot=$png", ('file:///' + $html.Replace('\', '/')))
  $p = Start-Process $Edge -ArgumentList $argumentos -PassThru -WindowStyle Hidden
  if (-not $p.WaitForExit(60000)) { $p.Kill(); throw 'Edge nao terminou' }
  for ($i = 0; $i -lt 20 -and -not (Test-Path $png); $i++) { Start-Sleep -Milliseconds 500 }
  if (-not (Test-Path $png)) { throw "O Edge nao gerou a imagem de $svg" }
  Move-Item -Force $png $destino
  Remove-Item $html
}

# Recorta as bordas transparentes
function Recortar([Drawing.Bitmap]$orig, [int]$folga) {
  $minX = $orig.Width; $minY = $orig.Height; $maxX = 0; $maxY = 0
  for ($y = 0; $y -lt $orig.Height; $y += 2) {
    for ($x = 0; $x -lt $orig.Width; $x += 2) {
      if ($orig.GetPixel($x, $y).A -gt 8) {
        if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }
  if ($maxX -le $minX) { throw 'imagem vazia' }
  $minX = [math]::Max(0, $minX - $folga); $minY = [math]::Max(0, $minY - $folga)
  $largura = [math]::Min($orig.Width - $minX, $maxX - $minX + 1 + 2 * $folga)
  $altura = [math]::Min($orig.Height - $minY, $maxY - $minY + 1 + 2 * $folga)
  return $orig.Clone((New-Object Drawing.Rectangle $minX, $minY, $largura, $altura), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

foreach ($arq in 'icone.svg', 'simbolo-branco.svg', 'logo.svg', 'logo-branco.svg') {
  if (-not (Test-Path "$PastaMarca\$arq")) { throw "Falta $arq na marca $PastaMarca" }
}
Render-Svg "$PastaMarca\icone.svg" 1024 1024 "$Saida\icone-1024.png"
Render-Svg "$PastaMarca\simbolo-branco.svg" 1024 1024 "$Saida\simbolo-1024.png"
$IconeMestre = New-Object Drawing.Bitmap "$Saida\icone-1024.png"
$tmp = New-Object Drawing.Bitmap "$Saida\simbolo-1024.png"
$SimboloMestre = Recortar $tmp 0
$tmp.Dispose()

function Desenhar([Drawing.Bitmap]$destino, [Drawing.Image]$imagem, [single]$x, [single]$y, [single]$l, [single]$a) {
  $g = [Drawing.Graphics]::FromImage($destino)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  $g.CompositingQuality = 'HighQuality'
  $g.DrawImage($imagem, (New-Object Drawing.RectangleF $x, $y, $l, $a))
  $g.Dispose()
}

# Icone completo (fundo + simbolo) no tamanho t
function Novo-Icone([int]$t) {
  $bmp = New-Object Drawing.Bitmap $t, $t, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  Desenhar $bmp $IconeMestre 0 0 $t $t
  return $bmp
}

# So o simbolo branco, com o lado maior ocupando $proporcao do quadrado
function Novo-Simbolo([int]$t, [double]$proporcao) {
  $bmp = New-Object Drawing.Bitmap $t, $t, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $escala = [double]($t * $proporcao) / [math]::Max($SimboloMestre.Width, $SimboloMestre.Height)
  $l = $SimboloMestre.Width * $escala; $a = $SimboloMestre.Height * $escala
  Desenhar $bmp $SimboloMestre (($t - $l) / 2) (($t - $a) / 2) $l $a
  return $bmp
}

# Circulo no degrade da marca com o simbolo (icone redondo do Android)
function Novo-Redondo([int]$t) {
  $bmp = New-Object Drawing.Bitmap $t, $t, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $fundo = New-Object Drawing.Drawing2D.LinearGradientBrush(
    (New-Object Drawing.Point 0, 0), (New-Object Drawing.Point $t, $t),
    [Drawing.ColorTranslator]::FromHtml($Marca.GradienteIcone[0]), [Drawing.ColorTranslator]::FromHtml($Marca.GradienteIcone[1]))
  $g.FillEllipse($fundo, 0, 0, $t - 1, $t - 1)
  $simbolo = Novo-Simbolo $t 0.66
  $g.DrawImage($simbolo, 0, 0, $t, $t)
  $simbolo.Dispose()
  $g.Dispose()
  return $bmp
}

function Salvar-Png([int]$t, [string]$caminho) {
  $b = Novo-Icone $t
  $b.Save($caminho, [Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()
}

function Dados-Dib($bmp) {
  $t = $bmp.Width
  $ms = New-Object IO.MemoryStream
  $w = New-Object IO.BinaryWriter $ms
  $w.Write([int]40); $w.Write([int]$t); $w.Write([int]($t * 2)); $w.Write([int16]1); $w.Write([int16]32)
  $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
  for ($y = $t - 1; $y -ge 0; $y--) {
    for ($x = 0; $x -lt $t; $x++) {
      $c = $bmp.GetPixel($x, $y)
      $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A)
    }
  }
  $linha = [int]([math]::Ceiling($t / 32.0) * 4)
  $w.Write((New-Object byte[] ($linha * $t)))
  $w.Flush()
  return ,$ms.ToArray()
}

function Dados-Png($bmp) {
  $ms = New-Object IO.MemoryStream
  $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
  return ,$ms.ToArray()
}

function Salvar-Ico([int[]]$tamanhos, [string]$caminho) {
  $blocos = @()
  foreach ($t in $tamanhos) {
    $b = Novo-Icone $t
    if ($t -ge 256) { $blocos += ,(Dados-Png $b) } else { $blocos += ,(Dados-Dib $b) }
    $b.Dispose()
  }
  $fs = [IO.File]::Create($caminho)
  $w = New-Object IO.BinaryWriter $fs
  $w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$tamanhos.Count)
  $pos = 6 + 16 * $tamanhos.Count
  for ($i = 0; $i -lt $tamanhos.Count; $i++) {
    $t = $tamanhos[$i]
    $lado = if ($t -ge 256) { 0 } else { $t }
    $w.Write([byte]$lado); $w.Write([byte]$lado); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$blocos[$i].Length); $w.Write([int]$pos)
    $pos += $blocos[$i].Length
  }
  foreach ($b in $blocos) { $w.Write([byte[]]$b) }
  $w.Close()
}

Salvar-Png 1024 "$Fonte\res\icon.png"
Salvar-Png 1024 "$Fonte\res\mac-icon.png"
Salvar-Png 256 "$Fonte\res\128x128@2x.png"
Salvar-Png 128 "$Fonte\res\128x128.png"
Salvar-Png 64 "$Fonte\res\64x64.png"
Salvar-Png 32 "$Fonte\res\32x32.png"
Salvar-Ico @(16, 32, 48, 64, 128) "$Fonte\res\icon.ico"
Salvar-Ico @(32) "$Fonte\res\tray-icon.ico"
Salvar-Ico @(16, 24, 32, 48, 64, 256) "$Fonte\flutter\windows\runner\resources\app_icon.ico"
Salvar-Png 512 "$Saida\previa-icone-512.png"
Salvar-Png 32 "$Saida\previa-icone-32.png"
# O icone do Flutter e o SVG da marca (sem <mask>: o flutter_svg desenha so clipPath e degrades)
Copy-Item -Force "$PastaMarca\icone.svg" "$Fonte\flutter\assets\icon.svg"

# --- Logos horizontais (tela inicial clara e escura), recortados ---
function Render-Logo([string]$svg, [string]$destino) {
  Render-Svg $svg 1200 600 "$Saida\logo-render.png"
  $orig = New-Object Drawing.Bitmap "$Saida\logo-render.png"
  $recorte = Recortar $orig 2
  $orig.Dispose()
  $recorte.Save($destino, [Drawing.Imaging.ImageFormat]::Png)
  "$destino $($recorte.Width)x$($recorte.Height)"
  $recorte.Dispose()
  Remove-Item "$Saida\logo-render.png"
}
Render-Logo "$PastaMarca\logo.svg" "$Fonte\flutter\assets\logo_light.png"
Render-Logo "$PastaMarca\logo-branco.svg" "$Fonte\flutter\assets\logo_dark.png"
Copy-Item -Force "$Fonte\flutter\assets\logo_light.png" "$Fonte\flutter\assets\logo.png"

# --- Icones do Android: cada arquivo mantem o tamanho original ---
Get-ChildItem "$Fonte\flutter\android\app\src\main\res\mipmap-*\*.png" | ForEach-Object {
  $orig = [Drawing.Image]::FromFile($_.FullName)
  $t = $orig.Width
  $orig.Dispose()
  $novo = switch ($_.Name) {
    'ic_launcher.png' { Novo-Icone $t }
    'ic_launcher_round.png' { Novo-Redondo $t }
    # A zona segura do icone adaptavel e o circulo central de 66 de 108 dp
    'ic_launcher_foreground.png' { Novo-Simbolo $t 0.56 }
    'ic_stat_logo.png' { Novo-Simbolo $t 0.86 }
    default { throw "icone inesperado: $($_.Name)" }
  }
  $novo.Save($_.FullName, [Drawing.Imaging.ImageFormat]::Png)
  $novo.Dispose()
}
$IconeMestre.Dispose()
$SimboloMestre.Dispose()
if (Test-Path "$Saida\perfil-edge") { Remove-Item -Recurse -Force "$Saida\perfil-edge" -ErrorAction SilentlyContinue }

# --- Textos e constantes ---
# Os arquivos sao lidos e gravados byte a byte (latin1), para nao mexer em nada alem do trecho trocado. O texto
# novo vira UTF-8 antes (acentos dos textos da marca)
$Latin = [Text.Encoding]::GetEncoding(28591)
function Em-Bytes([string]$s) { return $Latin.GetString([Text.Encoding]::UTF8.GetBytes($s)) }
function Trocar([string]$arquivo, [hashtable]$trocas) {
  $texto = $Latin.GetString([IO.File]::ReadAllBytes($arquivo))
  foreach ($de in $trocas.Keys) {
    $para = Em-Bytes $trocas[$de]
    if ($texto -match [regex]::Escape($para)) { continue }
    if ($texto -notmatch $de) { throw "nao encontrado em ${arquivo}: $de" }
    $texto = [regex]::Replace($texto, $de, $para.Replace('$', '$$'))
  }
  [IO.File]::WriteAllBytes($arquivo, $Latin.GetBytes($texto))
}


Trocar "$Fonte\libs\hbb_common\src\config.rs" @{
  'RwLock::new\("RustDesk"\.to_owned\(\)\)' = "RwLock::new(`"$NomeApp`".to_owned())"
  'RwLock::new\("com\.carriez"\.to_owned\(\)\)' = "RwLock::new(`"$($Marca.Organizacao)`".to_owned())"
  'RENDEZVOUS_SERVERS: &\[&str\] = &\["rs-ny\.rustdesk\.com"\]' = "RENDEZVOUS_SERVERS: &[&str] = &[`"$Servidor`"]"
  'RS_PUB_KEY: &str = "[^"]+"' = "RS_PUB_KEY: &str = `"$Chave`""
}
Trocar "$Fonte\Cargo.toml" @{
  'LegalCopyright = "[^"]*"' = "LegalCopyright = `"$Direitos`""
  '(?m)^ProductName = "RustDesk"' = "ProductName = `"$NomeExibido`""
  '(?m)^FileDescription = "RustDesk Remote Desktop"' = "FileDescription = `"$Descricao`""
}
Trocar "$Fonte\flutter\windows\runner\Runner.rc" @{
  'VALUE "CompanyName", "[^"]*"' = "VALUE `"CompanyName`", `"$Empresa`""
  'VALUE "FileDescription", "[^"]*"' = "VALUE `"FileDescription`", `"$Descricao`""
  'VALUE "LegalCopyright", "[^"]*"' = "VALUE `"LegalCopyright`", `"$Direitos`""
  'VALUE "ProductName", "RustDesk"' = "VALUE `"ProductName`", `"$NomeExibido`""
}
$CorPrincipal = Hex $Marca.CorPrincipal
Trocar "$Fonte\flutter\lib\common.dart" @{
  'static const Color accent = Color\(0xFF0071FF\)' = "static const Color accent = Color(0xFF$CorPrincipal)"
  'static const Color accent50 = Color\(0x770071FF\)' = "static const Color accent50 = Color(0x77$CorPrincipal)"
  'static const Color accent80 = Color\(0xAA0071FF\)' = "static const Color accent80 = Color(0xAA$CorPrincipal)"
  'static const Color idColor = Color\(0xFF00B6F0\)' = "static const Color idColor = Color(0xFF$(Hex $Marca.CorId))"
  'static const Color button = Color\(0xFF2C8CFF\)' = "static const Color button = Color(0xFF$CorPrincipal)"
}
# Android: o pacote de codigo continua com.carriez.flutter_hbb; muda so o identificador publicado
Trocar "$Fonte\flutter\android\app\src\main\AndroidManifest.xml" @{
  'android:label="RustDesk"' = "android:label=`"$NomeExibido`""
  'android:label="RustDesk Input"' = "android:label=`"$NomeExibido Input`""
  'android:scheme="rustdesk"' = "android:scheme=`"$($Marca.EsquemaUrl)`""
}
Trocar "$Fonte\flutter\android\app\src\main\res\values\strings.xml" @{
  '<string name="app_name">RustDesk</string>' = "<string name=`"app_name`">$NomeExibido</string>"
  'when RustDesk screen sharing' = "when $NomeExibido screen sharing"
  'Keeps the RustDesk remote desktop' = "Keeps the $NomeExibido remote desktop"
}
Trocar "$Fonte\flutter\android\app\build.gradle" @{
  'applicationId "com\.carriez\.flutter_hbb"' = "applicationId `"$($Marca.AndroidId)`""
}
Trocar "$Fonte\flutter\android\app\src\main\res\values\ic_launcher_background.xml" @{
  '#ffffff' = '#' + (Hex $Marca.CorFundoAndroid)
}
# Telas "Sobre": o site passa a ser o da marca e a declaracao de privacidade do RustDesk nao se aplica ao servidor proprio
Trocar "$Fonte\flutter\lib\mobile\pages\settings_page.dart" @{
  "const url = 'https://rustdesk\.com/'" = "const url = '$Site'"
  "Text\('rustdesk\.com'" = "Text('$SiteCurto'"
  'SettingsTile\(\s*title: Text\(translate\("Privacy Statement"\)\)' = 'if (!bind.isCustomClient()) SettingsTile(title: Text(translate("Privacy Statement"))'
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_setting_page.dart" @{
  "InkWell\(\s*onTap: \(\) \{\s*launchUrlString\('https://rustdesk\.com/privacy\.html'\);" = "if (!bind.isCustomClient()) InkWell(onTap: () { launchUrlString('https://rustdesk.com/privacy.html');"
  "launchUrlString\('https://rustdesk\.com'\)" = "launchUrlString('$($Site.TrimEnd('/'))')"
  "'Copyright " = "'$(Para-Dart $Empresa). Baseado no RustDesk. Copyright "
}
# O servidor embutido e proprio: sem isto, o cliente limita qualidade e FPS como se usasse o servidor publico
Trocar "$Fonte\src\common.rs" @{
  'pub fn using_public_server\(\) -> bool \{\s*crate::get_custom_rendezvous_server\(get_option\("custom-rendezvous-server"\)\)\.is_empty\(\)' = 'pub fn using_public_server() -> bool { false'
}
# Nomes dos arquivos (configuracao.ps1, Nome-Arquivo): suporte-vX.Y.Z-<perfil>-x64.exe abre a tela de instalacao,
# como o fim install.exe do RustDesk; o ...-x64-portable.exe continua portatil. O teste existe no programa e no
# empacotador (que acrescenta o --install)
Trocar "$Fonte\src\common.rs" @{
  'name\.to_lowercase\(\)\.ends_with\("install\.exe"\)' = '{ let n = name.to_lowercase(); n.ends_with("install.exe") || n.ends_with("-x64.exe") || n.ends_with("-x86.exe") }'
}
Trocar "$Fonte\libs\portable\src\main.rs" @{
  'let click_setup = args\.is_empty\(\) && arg_exe\.to_lowercase\(\)\.ends_with\("install\.exe"\);' = 'let click_setup = args.is_empty() && { let n = arg_exe.to_lowercase(); n.ends_with("install.exe") || n.ends_with("-x64.exe") || n.ends_with("-x86.exe") };'
}
# --dart-define=APP_TYPE no build do Flutter: tech no Tecnico e no Console, client no Cliente (o 4_compilar define
# CADENA_APP_TYPE pelo CADENA_PERFIL). No Dart: kCadenaAppType (cadena_console.dart)
Trocar "$Fonte\build.py" @{
  "system2\('flutter build windows --release'\)" = "system2('flutter build windows --release --dart-define=APP_TYPE=' + os.environ.get('CADENA_APP_TYPE', 'client'))"
}
# O servidor vem embutido, entao o rodape nao deve sugerir contratar um servidor no site do RustDesk
Trocar "$Fonte\flutter\lib\desktop\pages\connection_page.dart" @{
  'if \(!isIncomingOnly\) setupServerWidget\(\)' = 'if (!isIncomingOnly && !bind.isCustomClient()) setupServerWidget()'
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  'Color\.fromARGB\(255, 226, 66, 188\)' = "Color.fromARGB($(Argb $Marca.CorPrincipal))"
  'Color\.fromARGB\(255, 244, 114, 124\)' = "Color.fromARGB($(Argb $Marca.CorEscura))"
}
# Aviso de golpe do Android, com os textos da marca (AvisoAndroid)
$CorEscura = Hex $Marca.CorEscura
$LinhasAviso = ($Marca.AvisoAndroid | ForEach-Object { "'" + (Para-Dart $_) + "'" }) -join ', '
Trocar "$Fonte\flutter\lib\mobile\pages\server_page.dart" @{
  "import 'package:flutter/services\.dart';" = "import 'package:flutter/services.dart';`nimport 'package:flutter_svg/flutter_svg.dart';"
  'Color\(0xffe242bc\)' = "Color(0xff$((Hex $Marca.CorAvisoAndroid).ToLower()))"
  'Color\(0xfff4727c\)' = "Color.fromARGB($(Argb $Marca.CorEscura))"
  'translate\("Warning"\)' = "'Aviso'"
  "Image\.asset\(\s*'assets/scam\.png',\s*width: 180,\s*\)" = "Container(padding: EdgeInsets.all(2), decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(15)), child: SvgPicture.asset('assets/icon.svg', width: 64, height: 64))"
  'translate\("scam_title"\)' = "'Antes de liberar o acesso'"
  'Text\(\s*"\$\{translate\("scam_text1"\)\}\\n\\n\$\{translate\("scam_text2"\)\}\\n",\s*style: TextStyle\(\s*color: Colors\.white,\s*fontWeight: FontWeight\.bold,\s*fontSize: 16\.0,\s*\),\s*\),' = "...[$LinhasAviso].map((t) => Padding(padding: EdgeInsets.only(bottom: 13), child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0, height: 1.3)))),"
  'value: show_warning,' = "value: show_warning, side: BorderSide(color: Colors.white, width: 2), activeColor: Colors.white, checkColor: Color(0xff$($CorEscura.ToLower())),"
  'translate\("Don''t show again"\)' = "'Não mostrar novamente'"
  'isButtonLocked\s*\?\s*"\$\{translate\("I Agree"\)\} \(\$\{_countdown\}s\)"\s*:\s*translate\("I Agree"\),' = "'Continuar',"
  'translate\("Decline"\)' = "'Recusar'"
  'ElevatedButton\.styleFrom\(\s*backgroundColor: Colors\.blueAccent,\s*\)' = "ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Color(0xff$($CorEscura.ToLower())))"
}
# Perfis Cliente e Tecnico embutidos no lugar do custom.txt, que so o RustDesk Server Pro assina.
# Travam o servidor, escondem o que depende do Server Pro e escolhem o sentido da conexao
# Nome de cada servidor ao lado do "Pronto" (Nome no config.local.psd1)
$NomesServidores = ''
foreach ($s in $Srv1, $Srv2) {
  if ($s.Endereco) { $NomesServidores += "        `"$($s.Endereco.Split(':')[0])`" => `"$(Para-Rust $s.Nome)`".to_owned(),`n" }
}
$Perfis = @"
// Perfis da marca embutidos no executavel, no lugar do custom.txt que so o RustDesk Server Pro assina.
// Compilar com CADENA_PERFIL=tecnico gera a versao que so acessa; sem a variavel, a que so recebe acesso.
fn cadena_perfil() -> serde_json::Value {
    // CADENA_PERFIL=console: o Console Tecnico, igual ao Tecnico mas com nome proprio (acessos em abas)
    let console = option_env!("CADENA_PERFIL") == Some("console");
    let tecnico = console || option_env!("CADENA_PERFIL") == Some("tecnico");
    let mut travas = serde_json::json!({
        "hide-server-settings": "Y",
        "hide-network-settings": "Y",
        "hide-proxy-settings": "Y",
        "hide-websocket-settings": "Y",
        "hide-help-cards": "Y",
        "hide-powered-by-me": "Y",
        "disable-change-id": "Y",
        "disable-discovery-panel": "Y",
        "custom-rendezvous-server": "$Servidor",
        "key": "$Chave",
        "api-server": "$ApiServidor"
    });
    // Tema escuro por padrao: os estilos visuais (style_manager.dart) sao escuros e a barra de titulo acompanha
    let mut padrao = serde_json::json!({ "lang": "pt-br", "allow-auto-update": "Y", "theme": "dark" });
    if tecnico {
        padrao["allow-auto-record-outgoing"] = "Y".into();
    } else {
        // O cliente aprova cada acesso na janela que traz o aviso da marca. Trava (override), nao padrao: um padrao
        // perde para uma opcao ja gravada na maquina (visto em 2026-11-23: um Cliente em "senha ou clique" mostrava a
        // senha e o Console a pedia, e quem tem a senha entra sem o clique). Travado, ninguem muda nas Configuracoes
        travas["approve-mode"] = "click".into();
        // A aba "Grupo" (computadores dos clientes, vindos da API) so existe no Tecnico
        travas["disable-group-panel"] = "Y".into();
        travas["allow-numeric-one-time-password"] = "Y".into();
    }
    let mut perfil = serde_json::json!({
        "app-name": if console { "$NomeConsole" } else if tecnico { "$NomeTecnico" } else { "$NomeApp" },
        "conn-type": if tecnico { "outgoing" } else { "incoming" },
        "default-settings": padrao,
        "override-settings": travas
    });
    // O Cliente nao tem conta. O Tecnico entra na API (rustdesk-api-server-pro com os recursos do CadenaTech) e ve
    // os computadores na aba Clientes, separados por empresa. Nenhum dos dois tem catalogo de enderecos: as
    // empresas, os apelidos e as observacoes ficam no painel
    if !tecnico {
        perfil["disable-account"] = "Y".into();
    }
    perfil["disable-ab"] = "Y".into();
    perfil
}

// Servidor 2 (opcional), com a sua chave. O Cliente se registra no 1 e no 2 ao mesmo tempo; o Tecnico procura
// o ID no 1 e, se nao achar ou o 1 nao responder, no 2. Assim a queda de um servidor nao interrompe o suporte
pub const CADENA_SERVIDOR2: &str = "$Servidor2";
pub const CADENA_CHAVE2: &str = "$Chave2";

lazy_static::lazy_static! {
    // ID -> (id, servidor, chave) da segunda tentativa do Tecnico, lido por Client::_start
    pub static ref CADENA_TENTATIVA2: std::sync::Mutex<std::collections::HashMap<String, (String, String, String)>> = Default::default();
}

pub fn cadena_servidores_registro() -> Vec<String> {
    let mut lista = Config::get_rendezvous_servers();
    if !CADENA_SERVIDOR2.is_empty() && !lista.iter().any(|h| cadena_e_servidor2(h)) {
        lista.push(CADENA_SERVIDOR2.to_owned());
    }
    lista
}

fn cadena_e_servidor2(host: &str) -> bool {
    host == CADENA_SERVIDOR2 || host.starts_with(&format!("{}:", CADENA_SERVIDOR2))
}

/// Nome curto do servidor, para a tela (Nome do servidor no config.local.psd1)
pub fn cadena_nome_servidor(host: &str) -> String {
    let ip = host.split(':').next().unwrap_or(host);
    match ip {
$NomesServidores        _ => ip.to_owned(),
    }
}

lazy_static::lazy_static! {
    static ref CADENA_SERVIDORES_CACHE: std::sync::Mutex<(Option<std::time::Instant>, String)> = Default::default();
}

/// Servidores que respondem agora (porta 21116), mostrados ao lado do "Pronto": "Principal, Reserva".
/// Testa os dois em paralelo, com 2 s de prazo, e guarda o resultado por 20 s
pub fn cadena_servidores_conectados() -> String {
    {
        let c = CADENA_SERVIDORES_CACHE.lock().unwrap();
        if let Some(quando) = c.0 {
            if quando.elapsed() < std::time::Duration::from_secs(20) {
                return c.1.clone();
            }
        }
    }
    let testes: Vec<_> = cadena_servidores_registro()
        .into_iter()
        .map(|host| {
            std::thread::spawn(move || {
                use std::net::ToSocketAddrs;
                let alvo = if host.contains(':') { host.clone() } else { format!("{}:21116", host) };
                let ok = alvo
                    .to_socket_addrs()
                    .ok()
                    .and_then(|mut a| a.next())
                    .map(|a| std::net::TcpStream::connect_timeout(&a, std::time::Duration::from_secs(2)).is_ok())
                    .unwrap_or(false);
                (host, ok)
            })
        })
        .collect();
    let nomes: Vec<String> = testes
        .into_iter()
        .filter_map(|t| t.join().ok())
        .filter(|(_, ok)| *ok)
        .map(|(host, _)| cadena_nome_servidor(&host))
        .collect();
    let texto = nomes.join(", ");
    *CADENA_SERVIDORES_CACHE.lock().unwrap() = (Some(std::time::Instant::now()), texto.clone());
    texto
}

/// Chave do servidor ao qual a conexao vai: a do servidor 2 para ele, a configurada para o resto
pub fn cadena_chave_do_servidor(host: &str, chave: String) -> String {
    if !CADENA_SERVIDOR2.is_empty() && cadena_e_servidor2(host) {
        CADENA_CHAVE2.to_owned()
    } else {
        chave
    }
}

// Nome mostrado na tela, nos atalhos e em Programas instalados. O nome interno (sem espacos) fica nas pastas,
// no servico e no .exe, porque o RustDesk o usa sem aspas em comandos como "sc stop" e "taskkill"
pub fn cadena_nome_exibido() -> String {
    if option_env!("CADENA_PERFIL") == Some("console") {
        "$(Para-Rust $NomeExibidoConsole)".to_owned()
    } else if option_env!("CADENA_PERFIL") == Some("tecnico") {
        "$(Para-Rust $NomeExibidoTecnico)".to_owned()
    } else {
        "$(Para-Rust $NomeExibido)".to_owned()
    }
}

pub fn load_custom_client() {
    if let Ok(dados) = serde_json::from_value(cadena_perfil()) {
        aplicar_custom_client(dados);
    }
    // Envio das gravacoes por FTP (so age se o tecnico configurou, ver cadena_ftp.rs)
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::cadena_ftp::registrar();
}

#[allow(dead_code)]
fn load_custom_client_rustdesk() {
"@
$Perfis = $Perfis -replace "`r`n", "`n"
Trocar "$Fonte\src\common.rs" @{ 'pub fn load_custom_client\(\) \{' = $Perfis }
Trocar "$Fonte\src\common.rs" @{
  'let Ok\(mut data\) =\s*serde_json::from_slice::<std::collections::HashMap<String, serde_json::Value>>\(&data\)\s*else \{\s*log::error!\("Failed to parse custom client config"\);\s*return;\s*\};' = "let Ok(data) =`n        serde_json::from_slice::<std::collections::HashMap<String, serde_json::Value>>(&data)`n    else {`n        log::error!(`"Failed to parse custom client config`");`n        return;`n    };`n    aplicar_custom_client(data);`n}`n`nfn aplicar_custom_client(mut data: std::collections::HashMap<String, serde_json::Value>) {"
}
# Nome do tecnico: "<Tecnico>.exe --<prefixo>-nome Joao Silva" grava o nome num arquivo da pasta de configuracao,
# e cada conexao o envia ao cliente. Um arquivo, e nao o LocalConfig, porque o app aberto guarda o LocalConfig
# em memoria e o sobrescreveria. Sem o arquivo, o cliente continua vendo o usuario do Windows
$NomeCmd = @'
    // CadenaTech: grava o nome do tecnico, mostrado na janela do cliente a cada conexao (--__PREFIXO__-nome),
    // e testa o envio das gravacoes por FTP (--__PREFIXO__-ftp-teste, o mesmo teste da tela de configuracoes)
    if args.len() > 0 && (args[0] == "--__PREFIXO__-nome" || args[0] == "--__PREFIXO__-ftp-teste") {
        let texto = if args[0] == "--__PREFIXO__-ftp-teste" {
            #[cfg(not(any(target_os = "android", target_os = "ios")))]
            let t = crate::cadena_ftp::testar();
            #[cfg(any(target_os = "android", target_os = "ios"))]
            let t = String::new();
            t
        } else {
        let nome = args[1..].join(" ").trim().to_owned();
        let arquivo = config::Config::path("__PREFIXO__-nome-tecnico.txt");
        if let Some(pasta) = arquivo.parent() {
            std::fs::create_dir_all(pasta).ok();
        }
        match std::fs::write(&arquivo, &nome) {
            Err(e) => format!("N\u{e3}o foi poss\u{ed}vel salvar o nome: {}", e),
            Ok(_) if nome.is_empty() => {
                "Nome do t\u{e9}cnico removido. O cliente ver\u{e1} o usu\u{e1}rio do Windows.".to_owned()
            }
            Ok(_) => format!(
                "Nome do t\u{e9}cnico salvo: {}\n\nO cliente ver\u{e1} esse nome quando voc\u{ea} acessar o computador dele.",
                nome
            ),
        }
        };
        // Caixa com o nome do app, sem o titulo "RustDesk Output" nem a copia para a area de transferencia do my_println
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt;
            let largo = |s: &str| {
                std::ffi::OsStr::new(s)
                    .encode_wide()
                    .chain(Some(0))
                    .collect::<Vec<u16>>()
            };
            let (texto, titulo) = (largo(&texto), largo(&crate::common::cadena_nome_exibido()));
            unsafe {
                winapi::um::winuser::MessageBoxW(
                    std::ptr::null_mut(),
                    texto.as_ptr(),
                    titulo.as_ptr(),
                    winapi::um::winuser::MB_OK | winapi::um::winuser::MB_ICONINFORMATION,
                );
            }
        }
        #[cfg(not(windows))]
        println!("{}", texto);
        return None;
    }
    if args.len() > 0 {
        if args[0] == "--version" {
'@
$NomeCmd = ($NomeCmd -replace "`r`n", "`n").Replace('__PREFIXO__', $Prefixo)
Trocar "$Fonte\src\core_main.rs" @{
  'if args\.len\(\) > 0 \{\r?\n        if args\[0\] == "--version" \{' = $NomeCmd.Substring(4)
}
$NomeLer = @'
let mut display_name = get_builtin_option(keys::OPTION_DISPLAY_NAME);
        if display_name.is_empty() {
            display_name = std::fs::read_to_string(Config::path("__PREFIXO__-nome-tecnico.txt"))
                .unwrap_or_default()
                .trim()
                .to_owned();
        }
'@
$NomeLer = ($NomeLer -replace "`r`n", "`n").TrimEnd("`n").Replace('__PREFIXO__', $Prefixo)
Trocar "$Fonte\src\client.rs" @{
  'let mut display_name = get_builtin_option\(keys::OPTION_DISPLAY_NAME\);' = $NomeLer
}
# Instalacao: o pacote portatil entrega rustdesk.exe, mas o servico e os atalhos apontam para <app>.exe.
# A atualizacao (update_me) ja renomeia; a instalacao (install_me) nao, e o servico nunca iniciava
# Certificado da marca: a instalacao e a atualizacao (as duas rodam como administrador) gravam o certificado
# publico em Raiz Confiavel e Editores Confiaveis, para o Windows reconhecer a assinatura dos executaveis.
# O certificado so assina codigo (EKU) e nao emite outros (CA=0). Sem CertificadoB64, nao grava nada
Trocar "$Fonte\src\platform\windows.rs" @{
  'md \\"\{path\}\\"\r?\n\{copy_exe\}\r?\nreg add \{subkey\} /f\r?\n' = "md \`"{path}\`"`n{copy_exe}`n{rename_exe}`n{cadena_confiar}`nreg add {subkey} /f`n"
  'copy_exe = copy_exe_cmd\(&src_exe, &exe, &path\)\?,\r?\n        import_config = get_import_config\(&exe\),' = "copy_exe = copy_exe_cmd(&src_exe, &exe, &path)?,`n        rename_exe = rename_exe_cmd(&src_exe, &path)?,`n        cadena_confiar = cadena_confiar_cmd(&path),`n        import_config = get_import_config(&exe),"
  '\{rename_exe\}\r?\n\{remove_meta_toml\}' = "{rename_exe}`n{cadena_confiar}`n{remove_meta_toml}"
  'rename_exe = rename_exe_cmd\(&src_exe, &path\)\?,\r?\n        remove_meta_toml = ' = "rename_exe = rename_exe_cmd(&src_exe, &path)?,`n        cadena_confiar = cadena_confiar_cmd(&path),`n        remove_meta_toml = "
}
$Confiar = @'
// CadenaTech: grava o certificado da marca como confiavel (Raiz e Editores Confiaveis). Gerado pelo 2_marca.ps1
const CADENA_CERTIFICADO: &str = "__CERTIFICADO__";

pub fn cadena_confiar_cmd(path: &str) -> String {
    if CADENA_CERTIFICADO.is_empty() {
        return "".to_owned();
    }
    format!(
        "
(echo {CADENA_CERTIFICADO})> \"{path}\\cadena-editor.b64\"
certutil -f -decode \"{path}\\cadena-editor.b64\" \"{path}\\cadena-editor.cer\" > nul
certutil -f -addstore Root \"{path}\\cadena-editor.cer\" > nul
certutil -f -addstore TrustedPublisher \"{path}\\cadena-editor.cer\" > nul
del /f /q \"{path}\\cadena-editor.b64\"
"
    )
}

#[inline]
pub fn remove_meta_toml_cmd(
'@
$Confiar = ($Confiar -replace "`r`n", "`n").Replace('__CERTIFICADO__', $CertificadoB64)
Trocar "$Fonte\src\platform\windows.rs" @{ '#\[inline\]\r?\npub fn remove_meta_toml_cmd\(' = $Confiar }
# Aviso da marca (AvisoJanela) na janela de aceitar o acesso (Windows)
$AvisoCm = @'
final showAccept = model.approveMode != 'password';
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showAccept && client.type_() == ClientType.remote)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(8),
            margin: EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
                color: Color(0xff__COR_ESCURA__),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              '__AVISO__',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w500),
            ),
          ),
'@
$AvisoCm = ($AvisoCm -replace "`r`n", "`n").TrimEnd("`n").Replace('__COR_ESCURA__', $CorEscura.ToLower()).Replace('__AVISO__', (Para-Dart $Marca.AvisoJanela))
Trocar "$Fonte\flutter\lib\desktop\pages\server_page.dart" @{
  'final showAccept = model\.approveMode != ''password'';\r?\n    return Column\(\r?\n      mainAxisAlignment: MainAxisAlignment\.end,\r?\n      children: \[' = $AvisoCm
}
# Tela inicial do Cliente no modo clique: sem o campo de senha vazio e com a frase de quem aprova o acesso
$TextoClique = @'
if (!isOutgoingOnly)
            ChangeNotifierProvider.value(
              value: gFFI.serverModel,
              child: Consumer<ServerModel>(
                builder: (context, model, child) => Text(
                  model.approveMode == 'click'
                      ? '__TEXTO_ID__'
                      : translate("desk_tip"),
                  overflow: TextOverflow.clip,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
'@
$TextoClique = ($TextoClique -replace "`r`n", "`n").TrimEnd("`n").Replace('__TEXTO_ID__', (Para-Dart $Marca.TextoId))
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  'if \(!isOutgoingOnly\)\r?\n            Text\(\r?\n              translate\("desk_tip"\),\r?\n              overflow: TextOverflow\.clip,\r?\n              style: Theme\.of\(context\)\.textTheme\.bodySmall,\r?\n            \),' = $TextoClique
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  'buildPasswordBoard2\(BuildContext context, ServerModel model\) \{' = "buildPasswordBoard2(BuildContext context, ServerModel model) {`n    if (model.approveMode == 'click') return Container();"
}
# Cliente: liga o servico sozinho ao abrir, em vez de mostrar "Servico nao esta em execucao" e o link "Iniciar
# servico" (cliente leigo nao sabe o que fazer). A opcao stop-service fica "Y" quando o servico foi removido ou a
# instalacao dele falhou, e vale tambem para o portatil (a configuracao do usuario e a mesma).
#  - portatil: so limpa a opcao, sem pedir nada;
#  - instalado: reinstala o servico do Windows (pede a confirmacao de administrador uma vez e reabre o programa).
# Tenta uma vez por abertura: se a pessoa recusar a confirmacao, o link continua la.
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  '  var svcStopped = false\.obs;' = "  var svcStopped = false.obs;`n  // CadenaTech: o Cliente liga o servico sozinho ao abrir (uma tentativa por abertura)`n  bool _cadenaServicoTentado = false;"
  '      final v = await mainGetBoolOption\(kOptionStopService\);\r?\n      if \(v != svcStopped\.value\) \{\r?\n        svcStopped\.value = v;\r?\n        setState\(\(\) \{\}\);\r?\n      \}' = "      final v = await mainGetBoolOption(kOptionStopService);`n      if (v != svcStopped.value) {`n        svcStopped.value = v;`n        setState(() {});`n      }`n      if (v && !_cadenaServicoTentado && !bind.isOutgoingOnly()) {`n        _cadenaServicoTentado = true;`n        await start_service(true);`n      }"
}
# Atualizacao MANUAL desde 2026-11-23: o instalador novo e entregue por fora, e nada mais vai para o GitHub. Os
# programas da marca (Cliente e Console) nao procuram versao nova: o check_update, chamado pelo laco do servico do
# Cliente e pelo botao do RustDesk, volta sem fazer nada no cliente customizado. A verificacao original do RustDesk
# (api.rustdesk.com) o proprio RustDesk ja desliga no cliente customizado (check_software_update e
# check_update_as_root). Para atualizar uma maquina, rode o instalador novo por cima.
# O CADENA_NUMERO continua: e o numero interno desta compilacao (numero.txt da entrega), conferido pelo 9_publicar.ps1
if (-not (Test-Path $ArqNumero)) { New-Item -ItemType Directory -Force (Split-Path $ArqNumero) | Out-Null; Set-Content -Encoding ascii $ArqNumero 1 }
$NumeroVersao = [int](Get-Content $ArqNumero -Raw).Trim()
Trocar "$Fonte\src\updater.rs" @{
  'fn check_update\(manually: bool\) -> ResultType<\(\)> \{' = "// CadenaTech: numero interno desta compilacao (numero.txt da entrega). Gerado pelo 2_marca.ps1`n#[allow(dead_code)]`npub const CADENA_NUMERO: u64 = $NumeroVersao;`n`nfn check_update(manually: bool) -> ResultType<()> {`n    // Vetor: atualizacao manual. O cliente customizado nao procura versao nova (nem no GitHub nem no RustDesk)`n    if crate::is_custom_client() {`n        return Ok(());`n    }"
}
# Android: sem backup automatico do Google, reinstalar volta o app ao estado inicial, inclusive o aviso de golpe
Trocar "$Fonte\flutter\android\app\src\main\AndroidManifest.xml" @{
  ('android:label="' + [regex]::Escape($NomeExibido) + '"\r?\n        android:roundIcon') = "android:label=`"$NomeExibido`"`n        android:allowBackup=`"false`"`n        android:roundIcon"
}
# Nome com espacos onde o usuario ve: textos traduzidos, bandeja, titulo da janela, Programas instalados e atalhos.
# O nome interno (sem espacos) continua nas pastas, no servico, no .exe, nos pipes e no link da bandeja
Trocar "$Fonte\src\lang.rs" @{
  'let app_name = crate::get_app_name\(\);\r?\n                if !app_name\.contains\("RustDesk"\)' = "let app_name = crate::common::cadena_nome_exibido();`n                if !app_name.contains(`"RustDesk`")"
}
Trocar "$Fonte\src\tray.rs" @{
  'crate::get_app_name\(\),\r?\n                translate\("Service is running"' = "crate::common::cadena_nome_exibido(),`n                translate(`"Service is running`""
  'crate::get_app_name\(\),\r?\n                translate\("Ready"' = "crate::common::cadena_nome_exibido(),`n                translate(`"Ready`""
}
Trocar "$Fonte\src\platform\windows.rs" @{
  'let app_name = crate::get_app_name\(\);\r?\n\r?\n    let current_exe = std::env::current_exe\(\)\?;' = "let app_name = crate::get_app_name();`n    let nome_exibido = crate::common::cadena_nome_exibido();`n`n    let current_exe = std::env::current_exe()?;"
  '&format!\("\{app_name\}\.lnk"\),' = '&format!("{nome_exibido}.lnk"),'
  'crate::get_app_name\(\)\r?\n        \);\r?\n        reg_value_desktop_shortcuts = "1"' = "nome_exibido`n        );`n        reg_value_desktop_shortcuts = `"1`""
  'copy /Y \\"\{tmp_path\}\\\\\{app_name\}\.lnk\\" \\"\{start_menu\}' = 'copy /Y \"{tmp_path}\\{nome_exibido}.lnk\" \"{start_menu}'
  'if exist \\"\{tmp_path\}\\\\\{app_name\}\.lnk\\" del /f /q \\"\{tmp_path\}\\\\\{app_name\}\.lnk\\"' = 'if exist \"{tmp_path}\\{nome_exibido}.lnk\" del /f /q \"{tmp_path}\\{nome_exibido}.lnk\"'
  '/v DisplayName /t REG_SZ /d \\"\{app_name\}\\"' = '/v DisplayName /t REG_SZ /d \"{nome_exibido}\"'
  '/v Publisher /t REG_SZ /d \\"\{app_name\}\\"' = "/v Publisher /t REG_SZ /d \`"$(Para-Rust $Empresa)\`""
  'if exist \\"%PUBLIC%\\\\Desktop\\\\\{app_name\}\.lnk\\" del /f /q \\"%PUBLIC%\\\\Desktop\\\\\{app_name\}\.lnk\\"' = 'if exist \"%PUBLIC%\\Desktop\\{nome_exibido}.lnk\" del /f /q \"%PUBLIC%\\Desktop\\{nome_exibido}.lnk\"'
  'uninstall_amyuni_idd=get_uninstall_amyuni_idd\(\),' = "uninstall_amyuni_idd=get_uninstall_amyuni_idd(),`n        nome_exibido = crate::common::cadena_nome_exibido(),"
}
$NomeDart = @'
// CadenaTech: nome com espacos para a tela; o nome interno do app nao tem espacos
String cadenaNomeExibido() {
  final nome = bind.mainGetAppNameSync();
  if (nome == '__NOME_CLIENTE__') return '__EXIBIDO_CLIENTE__';
  if (nome == '__NOME_TECNICO__') return '__EXIBIDO_TECNICO__';
  if (nome == '__NOME_CONSOLE__') return '__EXIBIDO_CONSOLE__';
  return nome;
}

String getWindowName({WindowType? overrideType}) {
  final name = cadenaNomeExibido();
'@
$NomeDart = $NomeDart.Replace('__NOME_CLIENTE__', $NomeApp).Replace('__NOME_TECNICO__', $NomeTecnico).Replace('__EXIBIDO_CLIENTE__', (Para-Dart $NomeExibido)).Replace('__EXIBIDO_TECNICO__', (Para-Dart $NomeExibidoTecnico)).Replace('__NOME_CONSOLE__', $NomeConsole).Replace('__EXIBIDO_CONSOLE__', (Para-Dart $NomeExibidoConsole))
Trocar "$Fonte\flutter\lib\common.dart" @{
  'String getWindowName\(\{WindowType\? overrideType\}\) \{\r?\n  final name = bind\.mainGetAppNameSync\(\);' = ($NomeDart -replace "`r`n", "`n")
}
Trocar "$Fonte\flutter\lib\mobile\pages\home_page.dart" @{
  'return Text\(bind\.mainGetAppNameSync\(\)\);' = 'return Text(cadenaNomeExibido());'
}

# Envio das gravacoes por FTP (Tecnico). O modulo e um arquivo novo: "git add -N" o inclui no git diff que
# gera o rustdesk.patch da pasta fonte, usado tambem pelo Android
$FtpRs = [IO.File]::ReadAllText("$PSScriptRoot\modelos\cadena_ftp.rs", [Text.Encoding]::UTF8)
$FtpRs = $FtpRs.Replace('__PREFIXO__', $Prefixo).Replace('__TESTE__', (Para-Rust $NomeExibidoTecnico))
[IO.File]::WriteAllText("$Fonte\src\cadena_ftp.rs", ($FtpRs -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
& git -C $Fonte add -N src/cadena_ftp.rs
Trocar "$Fonte\src\lib.rs" @{
  '(?m)^mod updater;' = "mod updater;`n#[cfg(not(any(target_os = `"android`", target_os = `"ios`")))]`nmod cadena_ftp;"
}
# Tela do FTP no Tecnico (Configuracoes > Geral), sem mexer na ponte Flutter/Rust: usa mainGetCommon/mainSetCommon
Trocar "$Fonte\src\flutter_ffi.rs" @{
  'pub fn main_get_common\(key: String\) -> String \{' = "pub fn main_get_common(key: String) -> String {`n    // CadenaTech: Console Tecnico (CADENA_PERFIL=console) abre os acessos em abas na janela principal`n    if key == `"cadena-console`" {`n        return if option_env!(`"CADENA_PERFIL`") == Some(`"console`") { `"Y`" } else { `"`" }.to_owned();`n    }`n    // CadenaTech: servidores que respondem, mostrados ao lado do `"Pronto`"`n    if key == `"cadena-servidores`" {`n        return crate::common::cadena_servidores_conectados();`n    }`n    // CadenaTech: tela do envio das gravacoes por FTP`n    #[cfg(not(any(target_os = `"android`", target_os = `"ios`")))]`n    {`n        if key == `"cadena-ftp-estado`" {`n            return crate::cadena_ftp::estado_json();`n        }`n        if key == `"cadena-ftp-testar`" {`n            return crate::cadena_ftp::testar();`n        }`n    }"
  'pub fn main_set_common\(_key: String, _value: String\) \{' = "pub fn main_set_common(_key: String, _value: String) {`n    // CadenaTech: tela do envio das gravacoes por FTP`n    #[cfg(not(any(target_os = `"android`", target_os = `"ios`")))]`n    {`n        if _key == `"cadena-ftp-salvar`" {`n            crate::cadena_ftp::salvar_json(&_value);`n            return;`n        }`n        if _key == `"cadena-ftp-desligar`" {`n            crate::cadena_ftp::desligar();`n            return;`n        }`n    }"
}
# Cliente (cadena_cm.dart): a janela de aprovacao abre ao lado da janela principal. A principal e outro processo:
# acha pelo titulo (o nome exibido da marca) na classe das janelas do Flutter, fora deste processo, visivel e nao
# minimizada. A de aprovacao e a janela Flutter deste processo. Vai a direita da principal; sem espaco no monitor,
# a esquerda; sempre dentro da area de trabalho. Sem a principal na tela, nada muda (fica no canto do RustDesk)
$JanelaPrincipal = @'
pub fn main_set_common(_key: String, _value: String) {
    // CadenaTech: Cliente, janela de aprovacao ao lado da janela principal (cadena_cm.dart)
    #[cfg(target_os = "windows")]
    if _key == "cadena-cm-ao-lado" {
        use winapi::shared::windef::{HWND, RECT};
        use winapi::um::winuser::{
            FindWindowExW, GetMonitorInfoW, GetWindowRect, GetWindowThreadProcessId, IsIconic,
            IsWindowVisible, MonitorFromWindow, SetWindowPos, MONITORINFO,
            MONITOR_DEFAULTTONEAREST, SWP_NOACTIVATE, SWP_NOSIZE, SWP_NOZORDER,
        };
        let largo = |s: &str| s.encode_utf16().chain(Some(0)).collect::<Vec<u16>>();
        let classe = largo("FLUTTER_RUNNER_WIN32_WINDOW");
        let titulo = largo(&crate::common::cadena_nome_exibido());
        let pid_de = |h: HWND| {
            let mut pid = 0u32;
            unsafe { GetWindowThreadProcessId(h, &mut pid) };
            pid
        };
        let eu = std::process::id();
        let (mut principal, mut aprovacao): (HWND, HWND) =
            (std::ptr::null_mut(), std::ptr::null_mut());
        let mut h: HWND = std::ptr::null_mut();
        loop {
            h = unsafe { FindWindowExW(std::ptr::null_mut(), h, classe.as_ptr(), titulo.as_ptr()) };
            if h.is_null() {
                break;
            }
            if pid_de(h) != eu && unsafe { IsWindowVisible(h) != 0 && IsIconic(h) == 0 } {
                principal = h;
                break;
            }
        }
        h = std::ptr::null_mut();
        loop {
            h = unsafe { FindWindowExW(std::ptr::null_mut(), h, classe.as_ptr(), std::ptr::null()) };
            if h.is_null() {
                break;
            }
            if pid_de(h) == eu {
                aprovacao = h;
                break;
            }
        }
        if principal.is_null() || aprovacao.is_null() {
            return;
        }
        unsafe {
            let mut p: RECT = std::mem::zeroed();
            let mut a: RECT = std::mem::zeroed();
            if GetWindowRect(principal, &mut p) == 0 || GetWindowRect(aprovacao, &mut a) == 0 {
                return;
            }
            let mut info: MONITORINFO = std::mem::zeroed();
            info.cbSize = std::mem::size_of::<MONITORINFO>() as u32;
            let monitor = MonitorFromWindow(principal, MONITOR_DEFAULTTONEAREST);
            if GetMonitorInfoW(monitor, &mut info) == 0 {
                return;
            }
            let area = info.rcWork;
            let (largura, altura) = (a.right - a.left, a.bottom - a.top);
            let espaco = 8;
            let mut x = p.right + espaco;
            if x + largura > area.right {
                x = p.left - espaco - largura;
            }
            x = x.max(area.left).min(area.right - largura);
            let y = p.top.max(area.top).min(area.bottom - altura);
            SetWindowPos(
                aprovacao,
                std::ptr::null_mut(),
                x,
                y,
                0,
                0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        return;
    }
'@
$JanelaPrincipal = ($JanelaPrincipal -replace "`r`n", "`n").TrimEnd("`n")
Trocar "$Fonte\src\flutter_ffi.rs" @{ 'pub fn main_set_common\(_key: String, _value: String\) \{' = $JanelaPrincipal }
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_setting_page.dart" @{
  'if \(!isWeb\) record\(context\),' ="if (!isWeb) record(context),`n        if (!isWeb && bind.isOutgoingOnly()) const _CadenaFtp(),"
}
# A tela do FTP (so ASCII, acentos como ç) vai no fim do desktop_setting_page.dart
$Config = "$Fonte\flutter\lib\desktop\pages\desktop_setting_page.dart"
$TextoConfig = $Latin.GetString([IO.File]::ReadAllBytes($Config))
$Tela = [IO.File]::ReadAllText("$PSScriptRoot\modelos\cadena_ftp_tela.dart") -replace "`r`n", "`n"
[IO.File]::WriteAllBytes($Config, $Latin.GetBytes($TextoConfig + $Tela))

# Tela inicial do Tecnico no visual aprovado (2026-11-08): lateral com as secoes e a conta, barra de cima com ID, busca
# e visao, e o cartao novo. A lista, o status online e os menus continuam os do RustDesk; muda so a aparencia.
# Os dois modelos vao como arquivos proprios (UTF-8); o cartao e "part of" do peer_card.dart para usar o menu dele
Copy-Item -Force "$PSScriptRoot\modelos\cadena_inicio.dart" "$Fonte\flutter\lib\desktop\pages\cadena_inicio.dart"
# Estilos visuais do Cliente e do Tecnico (Glass & Glow, Onyx Minimal, Modular Space), trocados na hora pela paleta
New-Item -ItemType Directory -Force "$Fonte\flutter\lib\theme" | Out-Null
Copy-Item -Force "$PSScriptRoot\modelos\cadena_estilos.dart" "$Fonte\flutter\lib\theme\style_manager.dart"
& git -C $Fonte add -N flutter/lib/theme/style_manager.dart
# Tela do Cliente (aprovada em 2026-11-12): logo, slogan, ID grande, WhatsApp do suporte e Sair. Slogan e WhatsApp
# (so numeros, com DDI e DDD) vem do marca.psd1; vazios, a linha e o botao nao aparecem
$Whats = ("$($Marca.WhatsApp)" -replace '\D', '')
$TelaCliente = [IO.File]::ReadAllText("$PSScriptRoot\modelos\cadena_cliente.dart", [Text.Encoding]::UTF8).Replace('__SLOGAN__', (Para-Dart "$($Marca.Slogan)")).Replace('__WHATSAPP__', $Whats).Replace('__EMPRESA__', (Para-Dart $Empresa))
[IO.File]::WriteAllText("$Fonte\flutter\lib\desktop\pages\cadena_cliente.dart", $TelaCliente, (New-Object Text.UTF8Encoding $false))
& git -C $Fonte add -N flutter/lib/desktop/pages/cadena_cliente.dart
# Cliente instalado: o RustDesk mostra um "Quit" nos cartoes de ajuda quando nao ha outro cartao, e a tela nova ja
# tem o Sair (kCadenaSairNaTela, cadena_cliente.dart)
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  '    if \(bind\.isIncomingOnly\(\)\) \{\r?\n      return Align\(\r?\n        alignment: Alignment\.centerRight,\r?\n        child: OutlinedButton\(' = "    // CadenaTech: sem o Quit do RustDesk no Cliente; a tela dele ja tem o Sair (cadena_cliente.dart)`n    if (bind.isIncomingOnly() && !kCadenaSairNaTela) {`n      return Align(`n        alignment: Alignment.centerRight,`n        child: OutlinedButton("
}
# Tela de instalacao sem escolhas para o usuario final (Vetor, 2026-11-23): caminho padrao (Program Files\<nome>),
# atalhos no Menu Iniciar e na Area de Trabalho sempre ligados, sem a impressora remota (ela apareceria na lista de
# impressoras do cliente e leva documentos para o tecnico), sem o aviso de licenca do RustDesk e sem "Executar sem
# instalar". Ficam o titulo, uma frase e os botoes Cancelar e Instalar. Vale para o Cliente e o Console
$TelaInstalacao = @'
  @override
  Widget build(BuildContext context) {
    final double em = 13;
    // CadenaTech: instalacao sem escolhas (2_marca.ps1): caminho padrao, atalhos sempre, sem impressora, sem licenca
    return Scaffold(
        backgroundColor: null,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Installation'),
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('O ${cadenaNomeExibido()} será instalado neste computador.',
                      style: const TextStyle(fontSize: 15))
                  .marginSymmetric(vertical: 2 * em),
              Row(
                children: [
                  Expanded(
                    // NOT use Offstage to wrap LinearProgressIndicator
                    child: Obx(() => showProgress.value
                        ? LinearProgressIndicator().marginOnly(right: 10)
                        : Offstage()),
                  ),
                  Obx(
                    () => OutlinedButton.icon(
                      icon: Icon(Icons.close_rounded, size: 16),
                      label: Text(translate('Cancel')),
                      onPressed: cancelEnabled.value
                          ? () => windowManager.close()
                          : null,
                      style: buttonStyle,
                    ).marginOnly(right: 10),
                  ),
                  Obx(
                    () => ElevatedButton.icon(
                      icon: Icon(Icons.done_rounded, size: 16),
                      label: const Text('Instalar'),
                      onPressed: btnEnabled.value ? install : null,
                      style: buttonStyle,
                    ),
                  ),
                ],
              )
            ],
          ).paddingSymmetric(horizontal: 4 * em, vertical: 3 * em),
        ));
  }

  Future<void> install() async {
'@
$TelaInstalacao = ($TelaInstalacao -replace "`r`n", "`n").TrimEnd("`n")
Trocar "$Fonte\flutter\lib\desktop\pages\install_page.dart" @{
  '(?s)  @override\r?\n  Widget build\(BuildContext context\) \{\r?\n    final double em = 13;.*?\r?\n  Future<void> install\(\) async \{' = $TelaInstalacao
  "import 'package:url_launcher/url_launcher_string\.dart';" = '// CadenaTech: sem o link do acordo de licenca, o url_launcher_string nao e mais usado'
  "      if \(startmenu\.value\) args \+= ' startmenu';\r?\n      if \(desktopicon\.value\) args \+= ' desktopicon';\r?\n      if \(printer\.value\) args \+= ' printer';" = "      // CadenaTech: sempre com os atalhos e sem a impressora (a tela nao mostra as opcoes)`n      args = ' startmenu desktopicon';"
}
# Liberacao do acesso (Vetor, 2026-11-23). O Cliente so aceita pedido de conexao com a liberacao aberta pelo proprio
# cliente (cadena-liberado-ate, gravada pela janela: cadena_cliente.dart) ou com um atendimento ja em andamento
# (AUTHED_CONNS: ex. a transferencia de arquivo aberta no meio do acesso). Fora dela, recusa antes da janela de
# aprovacao, sem mostrar nada ao cliente, com a mensagem para o tecnico. O portao fica antes da "sessao recente"
# (reconexao rapida), entao tambem a bloqueia. Ao fim de cada atendimento autorizado, a liberacao vai a agora + 10 min
# (para reconectar e para reiniciar o computador). Liberacao mais longa que 30 min e ignorada: nem uma opcao
# adulterada deixa o acesso aberto indefinidamente. So vale no Cliente (incoming-only)
$Liberacao = @'
// CadenaTech: liberacao do acesso no Cliente (ver cadena_cliente.dart, _CadenaLiberacao)
const CADENA_LIBERADO_ATE: &str = "cadena-liberado-ate";
const CADENA_PRAZO_S: i64 = 600;
const CADENA_PRAZO_MAX_S: i64 = 1800;
const CADENA_MSG_FECHADO: &str =
    "O cliente não liberou o acesso. Peça para ele abrir o Suporte Vetor Sistemas e tente de novo.";

fn cadena_agora() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn cadena_liberado() -> bool {
    if !hbb_common::config::is_incoming_only() {
        return true;
    }
    if !AUTHED_CONNS.lock().unwrap().is_empty() {
        return true;
    }
    let ate = hbb_common::config::Config::get_option(CADENA_LIBERADO_ATE)
        .parse::<i64>()
        .unwrap_or(0);
    let agora = cadena_agora();
    ate >= agora && ate <= agora + CADENA_PRAZO_MAX_S
}

fn cadena_estender_liberacao() {
    if !hbb_common::config::is_incoming_only() {
        return;
    }
    let novo = cadena_agora() + CADENA_PRAZO_S;
    let atual = hbb_common::config::Config::get_option(CADENA_LIBERADO_ATE)
        .parse::<i64>()
        .unwrap_or(0);
    if novo > atual {
        hbb_common::config::Config::set_option(CADENA_LIBERADO_ATE.to_owned(), novo.to_string());
    }
}

impl Drop for Connection {
'@
$Liberacao = ($Liberacao -replace "`r`n", "`n").TrimEnd("`n")
Trocar "$Fonte\src\server\connection.rs" @{
  '(?m)^impl Drop for Connection \{' = $Liberacao
  '            self\.reset_session_scope_for_login\(\);\r?\n            if !self\.check_id_whitelist\(\)\.await \{\r?\n                return false;\r?\n            \}' = "            self.reset_session_scope_for_login();`n            if !self.check_id_whitelist().await {`n                return false;`n            }`n            // CadenaTech: so com a liberacao do cliente aberta (cadena_liberado)`n            if !cadena_liberado() {`n                log::info!(`"CadenaTech: acesso de {} recusado, liberacao fechada`", lr.my_id);`n                self.send_login_error(CADENA_MSG_FECHADO).await;`n                sleep(1.).await;`n                return false;`n            }"
  '    async fn on_close\(&mut self, reason: &str, lock: bool\) \{\r?\n        if self\.closed \{\r?\n            return;\r?\n        \}\r?\n        self\.closed = true;' = "    async fn on_close(&mut self, reason: &str, lock: bool) {`n        if self.closed {`n            return;`n        }`n        self.closed = true;`n        // CadenaTech: fim de um atendimento autorizado: liberacao por mais CADENA_PRAZO_S`n        if self.authorized {`n            cadena_estender_liberacao();`n        }"
}
Copy-Item -Force "$PSScriptRoot\modelos\cadena_cartao.dart" "$Fonte\flutter\lib\common\widgets\cadena_cartao.dart"
& git -C $Fonte add -N flutter/lib/desktop/pages/cadena_inicio.dart flutter/lib/common/widgets/cadena_cartao.dart
# Cliente, janela de aprovacao (--cm), 2026-11-23: ganha o topo com logo, ID e servidores (cadena_cm.dart), fica mais
# alta para caber e abre ao lado da janela principal ("cadena-cm-ao-lado" no main_set_common, mais abaixo)
Copy-Item -Force "$PSScriptRoot\modelos\cadena_cm.dart" "$Fonte\flutter\lib\desktop\pages\cadena_cm.dart"
& git -C $Fonte add -N flutter/lib/desktop/pages/cadena_cm.dart
Trocar "$Fonte\flutter\lib\desktop\pages\server_page.dart" @{
  "import '../../models/server_model.dart';" = "import '../../models/server_model.dart';`nimport 'cadena_cm.dart';"
  '        _CmHeader\(client: client\),' = "        // CadenaTech: no Cliente, topo com logo, ID e servidores (cadena_cm.dart)`n        if (bind.isIncomingOnly()) const CadenaCmMarca(),`n        _CmHeader(client: client),"
}
# O RustDesk poe a janela de aprovacao no canto superior direito ao abrir e ao voltar depois de escondida (as duas
# chamadas de setSizeAlignment do showCmWindow); logo depois, o Cliente a leva para o lado da janela principal
Trocar "$Fonte\flutter\lib\main.dart" @{
  "import 'package:flutter_hbb/desktop/pages/server_page.dart';" = "import 'package:flutter_hbb/desktop/pages/server_page.dart';`nimport 'package:flutter_hbb/desktop/pages/cadena_cm.dart';"
  'kConnectionManagerWindowSizeClosedChat, Alignment\.topRight\);' = "kConnectionManagerWindowSizeClosedChat, Alignment.topRight);`n    cadenaCmAoLado(); // CadenaTech: ao lado da janela principal (cadena_cm.dart)"
}
Trocar "$Fonte\flutter\lib\consts.dart" @{
  'const Size kConnectionManagerWindowSizeClosedChat = Size\(300, 490\);' = "// CadenaTech: mais alta para o topo com logo, ID e servidores (cadena_cm.dart)`nconst Size kConnectionManagerWindowSizeClosedChat = Size(300, 600);"
  'const Size kConnectionManagerWindowSizeOpenChat = Size\(700, 490\);' = 'const Size kConnectionManagerWindowSizeOpenChat = Size(700, 600);'
}
# Aba Clientes: a API manda o apelido do computador (definido no painel, tela Dispositivos) em "alias"; o cartao
# mostra o apelido no lugar do nome do computador. A empresa vem como grupo (device_group_name). O telefone e o
# sistema usado vao para cadenaExtras (cadena_console.dart), lidos pela linha do Tecnico e pela busca
Trocar "$Fonte\flutter\lib\common\hbbs\hbbs.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = "import 'package:flutter_hbb/consts.dart';`nimport 'package:flutter_hbb/desktop/pages/cadena_console.dart';"
  "  String\? device_group_name;\r?\n  String note = '';" = "  String? device_group_name;`n  String note = '';`n  // CadenaTech: apelido, telefone e sistema usado, definidos no painel da API`n  String alias = '';`n  String telefone = '';`n  String sistema = '';"
  "device_group_name = json\['device_group_name'\] \?\? '',\r?\n        note = json\['note'\] \?\? '';" = "device_group_name = json['device_group_name'] ?? '',`n        note = json['note'] ?? '',`n        alias = json['alias'] ?? '',`n        telefone = json['telefone'] ?? '',`n        sistema = json['sistema'] ?? '';"
  '  static Peer toPeer\(PeerPayload p\) \{\r?\n    return Peer\.fromJson\(\{' = "  static Peer toPeer(PeerPayload p) {`n    cadenaExtras[p.id] = (telefone: p.telefone, sistema: p.sistema);`n    return Peer.fromJson({"
  '"note": p\.note,' = "`"note`": p.note,`n      `"alias`": p.alias,"
}
Trocar "$Fonte\flutter\lib\common\widgets\peer_card.dart" @{
  "import 'dart:math' as math;" = "import 'dart:math' as math;`nimport 'package:flutter_hbb/theme/style_manager.dart';`n`n// CadenaTech: cartao do Tecnico`npart 'cadena_cartao.dart';"
  'Widget _buildPeerCard\(\r?\n      BuildContext context, Peer peer, Rx<BoxDecoration\?> deco\) \{' = "Widget _buildPeerCard(`n      BuildContext context, Peer peer, Rx<BoxDecoration?> deco) {`n    // CadenaTech: cartao novo no Tecnico (cadena_cartao.dart)`n    if (bind.isOutgoingOnly()) return _cadenaCartao(context, peer, deco);"
  # Visao em lista do Tecnico: linha com status, apelido, ID, telefone, sistema e o botao CONECTAR
  'Widget _buildPeerTile\(\r?\n      BuildContext context, Peer peer, Rx<BoxDecoration\?>\? deco\) \{' = "Widget _buildPeerTile(`n      BuildContext context, Peer peer, Rx<BoxDecoration?>? deco) {`n    // CadenaTech: linha nova no Tecnico (cadena_cartao.dart)`n    if (bind.isOutgoingOnly() && deco != null) {`n      return _cadenaLinha(context, peer, deco);`n    }"
}
# Busca do Tecnico ("Buscar ID, nome ou loja"): procura tambem na empresa (grupo), no telefone e no sistema
Trocar "$Fonte\flutter\lib\common.dart" @{
  '  if \(peer\.alias\.toLowerCase\(\)\.contains\(searchText\)\) \{' = "  // CadenaTech: empresa (grupo), telefone e sistema usado tambem entram na busca`n  if (peer.alias.toLowerCase().contains(searchText) ||`n      peer.device_group_name.toLowerCase().contains(searchText) ||`n      cadenaExtrasBusca(peer.id).contains(searchText)) {"
}
Trocar "$Fonte\flutter\lib\common\widgets\peers_view.dart" @{
  'Container\(height: 45, child: visibilityChild\)' = "Container(`n                          height: bind.isOutgoingOnly() ? 74 : 45,`n                          child: visibilityChild)"
  'width: 220, height: 140, child: visibilityChild\)' = "width: bind.isOutgoingOnly() ? 236 : 220,`n                              height: bind.isOutgoingOnly() ? 226 : 140,`n                              child: visibilityChild)"
}

# Console Tecnico (CADENA_PERFIL=console, prototipo aprovado em 2026-11-09): os acessos abrem em abas na janela
# principal; menu do cartao e clique direito na aba levam para janela separada, e a janela separada devolve. Tudo
# passa por cadenaConsole(), falso no Tecnico e no Cliente, entao eles continuam iguais
Copy-Item -Force "$PSScriptRoot\modelos\cadena_console.dart" "$Fonte\flutter\lib\desktop\pages\cadena_console.dart"
& git -C $Fonte add -N flutter/lib/desktop/pages/cadena_console.dart
$ImpConsole = "import 'package:flutter_hbb/consts.dart';`nimport 'package:flutter_hbb/desktop/pages/cadena_console.dart';"
Trocar "$Fonte\flutter\lib\common.dart" @{
  "import '../consts.dart';" = "import '../consts.dart';`nimport 'package:flutter_hbb/desktop/pages/cadena_console.dart';"
  '  \} else \{\r?\n    await rustDeskWinManager\.newRemoteDesktop\(id,' = "  } else {`n    // CadenaTech: no Console Tecnico o acesso abre numa aba da janela principal (cadena_console.dart)`n    if (cadenaAbrirNaAba(id,`n        password: password,`n        isSharedPassword: isSharedPassword,`n        forceRelay: forceRelay)) {`n      return;`n    }`n    await rustDeskWinManager.newRemoteDesktop(id,"
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_tab_page.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = $ImpConsole
  '            body: DesktopTab\(\r?\n              controller: tabController,' = "            body: DesktopTab(`n              controller: tabController,`n              // CadenaTech: Console Tecnico, nome e menu das abas de acesso (cadena_console.dart)`n              labelGetter: cadenaConsole() ? cadenaRotuloAba : null,`n              tabMenuBuilder: cadenaConsole()`n                  ? (key) => cadenaMenuDaAba(context, key)`n                  : null,"
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = $ImpConsole
  'rustDeskWinManager\.setMethodHandler\(\(call, fromWindowId\) async \{' = "rustDeskWinManager.setMethodHandler((call, fromWindowId) async {`n      // CadenaTech: Console Tecnico, acessos que vao e voltam das janelas separadas (cadena_console.dart)`n      if (cadenaChamadaDoConsole(call.method)) {`n        return await cadenaTratarChamada(call, fromWindowId);`n      }"
}
Trocar "$Fonte\flutter\lib\desktop\widgets\tabbar_widget.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = $ImpConsole
  '  void onWindowClose\(\) async \{' = "  void onWindowClose() async {`n    // CadenaTech: Console Tecnico, confirma antes de fechar a janela principal com acessos em abas`n    if (tabType == DesktopTabType.main &&`n        !await cadenaPodeFecharConsole(controller)) {`n      return;`n    }"
}
$Trazer = @'
    // CadenaTech: Console Tecnico, devolve o acesso para uma aba da janela principal (cadena_console.dart)
    final cadenaTrazer =
        cadenaItemTrazer(windowId(), key, '$sessionId', cancelFunc);
    if (cadenaTrazer != null) menu.insert(1, cadenaTrazer);
    if (perms['restart'] != false &&
'@
Trocar "$Fonte\flutter\lib\desktop\pages\remote_tab_page.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = $ImpConsole
  "    if \(perms\['restart'\] != false &&" = ($Trazer -replace "`r`n", "`n")
}
$NovaJanela = @'
  // CadenaTech: Console Tecnico, abre este acesso numa janela separada mesmo com as abas ligadas
  MenuEntryBase<String> _cadenaNovaJanelaAction(BuildContext context) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) =>
          Text('Abrir em nova janela', style: style),
      proc: () {
        cadenaForcarJanela = true;
        connectInPeerTab(context, peer, tab);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _connectAction(BuildContext context) {
'@
Trocar "$Fonte\flutter\lib\common\widgets\peer_card.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = $ImpConsole
  '  @protected\r?\n  MenuEntryBase<String> _connectAction\(BuildContext context\) \{' = ($NovaJanela -replace "`r`n", "`n")
  '    final List<MenuEntryBase<String>> menuItems = \[\r?\n      _connectAction\(context\),' = "    final List<MenuEntryBase<String>> menuItems = [`n      _connectAction(context),`n      if (cadenaConsole()) _cadenaNovaJanelaAction(context),"
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_setting_page.dart" @{
  "import 'package:flutter_hbb/consts.dart';" = $ImpConsole
  "          'Open connection in new tab',\r?\n          kOptionOpenNewConnInTabs,\r?\n          isServer: false,\r?\n        \)," = "          'Open connection in new tab',`n          kOptionOpenNewConnInTabs,`n          isServer: false,`n        ),`n        // CadenaTech: Console Tecnico, padrao de onde abrir os acessos (cadena_console.dart)`n        if (cadenaConsole())`n          _OptionCheckBox(`n            context,`n            'Abrir os acessos em janela separada (fora do console)',`n            kCadenaOpcaoJanela,`n            isServer: false,`n          ),"
}
# Configuracoes (aprovado em 2026-11-13): interruptores no lugar de todos os checkboxes (CadenaCheckbox, em
# style_manager.dart) e a secao "Outro" dividida em Interface e abas, Desempenho e renderizacao e Rede e conexao
# avancada, esta recolhida por padrao (cadena_outras_opcoes.dart). A tela de FTP ja foi juntada acima
$OutrasOpcoes = ([IO.File]::ReadAllText("$PSScriptRoot\modelos\cadena_outras_opcoes.dart", [Text.Encoding]::UTF8) -replace "`r`n", "`n").TrimEnd()
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_setting_page.dart" @{
  "import 'package:flutter_hbb/desktop/pages/cadena_console.dart';" = "import 'package:flutter_hbb/desktop/pages/cadena_console.dart';`nimport 'package:flutter_hbb/theme/style_manager.dart';"
  '(?<![A-Za-z_])Checkbox\(' = 'CadenaCheckbox('
  "(?s)  Widget other\(\) \{\r?\n.*?    return _Card\(title: 'Other', children: children\);\r?\n  \}" = $OutrasOpcoes
}
# Visual das Configuracoes (aprovado em 2026-11-13, modelos do usuario): cartoes no estilo atual, fundo do estilo,
# Tema numa linha, "Gravacao e Midia" com o codec, a aba Geral em duas colunas (FTP a direita) e a lateral com
# destaque. Os trechos novos ficam no cadena_config_geral.dart, cada um depois de //@@ nome
$Pecas = @{}
$NomePeca = $null
foreach ($linha in ([IO.File]::ReadAllText("$PSScriptRoot\modelos\cadena_config_geral.dart", [Text.Encoding]::UTF8) -replace "`r`n", "`n").Split("`n")) {
  if ($linha -match '^//@@ (\w+)') { $NomePeca = $Matches[1]; $Pecas[$NomePeca] = New-Object Collections.Generic.List[string]; continue }
  if ($NomePeca) { $Pecas[$NomePeca].Add($linha) }
}
function Peca([string]$nome) { return (($Pecas[$nome] -join "`n").TrimEnd()) }
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_setting_page.dart" @{
  "(?s)Widget _Card\(\r?\n    \{required String title,.*?\r?\n\}" = (Peca 'card')
  "(?s)    return _Card\(title: 'Theme', children: \[\r?\n.*?\r?\n    \]\);" = (Peca 'tema')
  "(?s)    final scrollController = ScrollController\(\);\r?\n    return ListView\(\r?\n      controller: scrollController,\r?\n      children: \[\r?\n        if \(!isWeb\) service\(\),.*?\)\.marginOnly\(bottom: _kListViewBottomMargin\);" = (Peca 'geral')
  "      return _Card\(title: 'Recording', children: \[" = (Peca 'gravacao')
  "    super\.build\(context\);\r?\n    return Scaffold\(\r?\n      backgroundColor: Theme\.of\(context\)\.colorScheme\.background,\r?\n      body: _buildBlock\(" = (Peca 'pagina')
  "    \);\r?\n  \}\r?\n\r?\n  Widget _header\(BuildContext context\) \{" = (Peca 'pagina_fim')
  "    final settingsText = Text\(\r?\n      translate\('Settings'\),\r?\n      textAlign: TextAlign\.left,\r?\n      style: const TextStyle\(\r?\n        color: _accentColor,\r?\n        fontSize: _kTitleFontSize,\r?\n        fontWeight: FontWeight\.w400," = (Peca 'titulo')
  "      return SizedBox\(\r?\n        width: _kTabWidth,\r?\n        height: _kTabHeight,\r?\n        child: InkWell\(" = (Peca 'item')
  'selected \? _accentColor : null' = 'selected ? cadenaCorSelecao : null'
}
# Na janela principal o stateGlobal.windowId e -1; o acesso em aba usa o id 0 (o da principal) para tela cheia,
# minimizar e o tamanho da janela. Nas janelas de acesso o id e sempre >= 1, entao nada muda nelas
Trocar "$Fonte\flutter\lib\models\state_model.dart" @{
  'final wc = WindowController\.fromWindowId\(windowId\);' = "// CadenaTech: Console Tecnico, acesso em aba na janela principal (id -1 = principal, que e a 0)`n      final wc = WindowController.fromWindowId(windowId < 0 ? kWindowMainId : windowId);"
}
Trocar "$Fonte\flutter\lib\desktop\widgets\remote_toolbar.dart" @{
  '  int get windowId => stateGlobal\.windowId;' = "  // CadenaTech: Console Tecnico, acesso em aba na janela principal (id -1 = principal, que e a 0)`n  int get windowId =>`n      stateGlobal.windowId < 0 ? kWindowMainId : stateGlobal.windowId;"
}
Trocar "$Fonte\flutter\lib\common\widgets\peer_tab_page.dart" @{
  'class PeerTabPage extends StatefulWidget \{' = "// CadenaTech: a lateral do Tecnico (cadena_inicio.dart) troca de aba e recarrega por aqui`nFuture<void> Function(int)? cadenaTrocarAba;`nvoid Function()? cadenaRecarregarAba;`n`nclass PeerTabPage extends StatefulWidget {"
  '_PeerTabPageState\(\) \{\r?\n    _loadLocalOptions\(\);\r?\n  \}' = "_PeerTabPageState() {`n    _loadLocalOptions();`n    cadenaTrocarAba = handleTabSelection;`n    cadenaRecarregarAba = () {`n      if (gFFI.peerTabModel.currentTab < entries.length) {`n        entries[gFFI.peerTabModel.currentTab].load?.call();`n      }`n    };`n  }"
  'children: \[\r?\n        Obx\(\(\) => SizedBox\(\r?\n              height: 32,' = "children: [`n        // CadenaTech: no Tecnico as abas ficam na lateral; o cabecalho so aparece na selecao multipla`n        if (!bind.isOutgoingOnly() || model.multiSelectionMode)`n        Obx(() => SizedBox(`n              height: 32,"
}
Trocar "$Fonte\flutter\lib\desktop\pages\desktop_home_page.dart" @{
  "import 'package:flutter_hbb/desktop/pages/connection_page.dart';" = "import 'package:flutter_hbb/desktop/pages/connection_page.dart';`nimport 'package:flutter_hbb/desktop/pages/cadena_inicio.dart';`nimport 'package:flutter_hbb/desktop/pages/cadena_cliente.dart';`nimport 'package:flutter_hbb/theme/style_manager.dart';"
  # Fundo e tema do estilo visual em volta da tela inicial (Cliente e Tecnico)
  '    return _buildBlock\(\r?\n        child: Row\(' = "    return _buildBlock(`n        // CadenaTech: fundo e tema do estilo visual (style_manager.dart)`n        child: CadenaFundo(child: Row("
  '        if \(!isIncomingOnly\) Expanded\(child: buildRightPane\(context\)\),\r?\n      \],\r?\n    \)\);' = "        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),`n      ],`n    )));"
  # O painel da direita recebe o context da pagina (acima do CadenaFundo): no Tecnico fica transparente para o fundo
  # do estilo aparecer
  '      color: Theme\.of\(context\)\.scaffoldBackgroundColor,\r?\n      child: ConnectionPage\(\),' = "      color: bind.isOutgoingOnly()`n          ? Colors.transparent`n          : Theme.of(context).scaffoldBackgroundColor,`n      child: ConnectionPage(),"
  '        buildLeftPane\(context\),\r?\n        if \(!isIncomingOnly\) const VerticalDivider\(width: 1\),' = "        // CadenaTech: lateral nova no Tecnico (cadena_inicio.dart)`n        bind.isOutgoingOnly() ? const CadenaLateral() : buildLeftPane(context),`n        if (!isIncomingOnly && !bind.isOutgoingOnly())`n          const VerticalDivider(width: 1),"
  # Cliente: tela nova (cadena_cliente.dart). O aviso de senha, os cartoes de ajuda (instalar, permissoes) e o
  # status continuam os do RustDesk, e a janela segue a altura medida pela _childKey
  '  Widget buildLeftPane\(BuildContext context\) \{\r?\n    final isIncomingOnly = bind\.isIncomingOnly\(\);' = "  Widget buildLeftPane(BuildContext context) {`n    final isIncomingOnly = bind.isIncomingOnly();`n    // CadenaTech: Cliente com a tela nova (cadena_cliente.dart)`n    if (isIncomingOnly) {`n      return CadenaPainelCliente(`n        chave: _childKey,`n        aviso: buildPresetPasswordWarning(),`n        ajuda: Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),`n        status: OnlineStatusWidget(`n          onSvcStatusChanged: () {`n            if (isInHomePage()) {`n              Future.delayed(Duration(milliseconds: 300), () {`n                _updateWindowSize();`n              });`n            }`n          },`n        ),`n        aoMudarTamanho: () {`n          if (isInHomePage()) _updateWindowSize();`n        },`n      );`n    }"
}
Trocar "$Fonte\flutter\lib\desktop\pages\connection_page.dart" @{
  "import '../../common/widgets/peer_tab_page.dart';" = "import '../../common/widgets/peer_tab_page.dart';`nimport 'cadena_inicio.dart';"
  'Row\(\r?\n              children: \[\r?\n                Flexible\(child: _buildRemoteIDTextField\(context\)\),\r?\n              \],\r?\n            \)\.marginOnly\(top: 22\),\r?\n            SizedBox\(height: 12\),\r?\n            Divider\(\)\.paddingOnly\(right: 12\),\r?\n            Expanded\(child: PeerTabPage\(\)\),\r?\n          \],\r?\n        \)\.paddingOnly\(left: 12\.0\)\),' = "// CadenaTech: no Tecnico, barra de cima e titulo da secao (cadena_inicio.dart)`n            if (isOutgoingOnly)`n              CadenaTopo(controlador: _idController, conectar: onConnect),`n            if (isOutgoingOnly) const CadenaTituloSecao().paddingOnly(left: 18),`n            if (!isOutgoingOnly)`n              Row(`n                children: [`n                  Flexible(child: _buildRemoteIDTextField(context)),`n                ],`n              ).marginOnly(top: 22),`n            if (!isOutgoingOnly) SizedBox(height: 12),`n            if (!isOutgoingOnly) Divider().paddingOnly(right: 12),`n            // CadenaTech: cadenaSoPorId (cadena_inicio.dart) = sem lista de computadores, so o ID que o cliente informa`n            Expanded(`n                child: isOutgoingOnly && cadenaSoPorId`n                    ? const CadenaSoId()`n                    : PeerTabPage().paddingOnly(`n                        left: isOutgoingOnly ? 18 : 0,`n                        right: isOutgoingOnly ? 6 : 0)),`n          ],`n        ).paddingOnly(left: isOutgoingOnly ? 0 : 12.0)),"
}
# "Pronto" com os servidores que respondem: "Pronto · Principal, Reserva". Nenhum respondendo: "Sem conexão com o
# servidor" e a bolinha vermelha. Antes do primeiro teste (null), fica o "Pronto" normal (Windows e Android)
Trocar "$Fonte\flutter\lib\desktop\pages\connection_page.dart" @{
  '  final _svcIsUsingPublicServer = true\.obs;' = "  final _svcIsUsingPublicServer = true.obs;`n  // CadenaTech: nomes dos servidores que respondem; null = ainda nao testado, vazio = nenhum`n  final _cadenaServidores = RxnString();"
  '    _svcIsUsingPublicServer\.value = await bind\.mainIsUsingPublicServer\(\);' = "    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();`n    _cadenaServidores.value = await bind.mainGetCommon(key: 'cadena-servidores');"
  'stateGlobal\.svcStatus\.value == SvcStatus\.ready\r?\n                        \? Color\.fromARGB\(255, 50, 190, 166\)' = "stateGlobal.svcStatus.value == SvcStatus.ready &&`n                            _cadenaServidores.value != ''`n                        ? Color.fromARGB(255, 50, 190, 166)"
  "                  : translate\('Ready'\)," = "                  : _cadenaServidores.value == ''`n                      ? 'Sem conexão com o servidor'`n                      : (_cadenaServidores.value == null`n                          ? translate('Ready')`n                          : 'Conectado de forma segura · `${_cadenaServidores.value}'),"
}
# No Tecnico (so acessa) a linha de status vinha escondida, porque ele nao se registra no servidor. Ela passa a
# aparecer e a depender so do teste dos servidores
Trocar "$Fonte\flutter\lib\desktop\pages\connection_page.dart" @{
  'if \(!isOutgoingOnly\) const Divider\(height: 1\),\r?\n        if \(!isOutgoingOnly\) OnlineStatusWidget\(\)' = "// CadenaTech: no Tecnico o status dos servidores e o operador ficam no rodape proprio (cadena_inicio.dart)`n        if (!isOutgoingOnly) const Divider(height: 1),`n        if (isOutgoingOnly) const CadenaRodape(),`n        if (!isOutgoingOnly) OnlineStatusWidget()"
  '                color: _svcStopped\.value \|\|' = "                color: bind.isOutgoingOnly()`n                    ? (_cadenaServidores.value == ''`n                        ? Color.fromARGB(255, 224, 79, 95)`n                        : Color.fromARGB(255, 50, 190, 166))`n                    : _svcStopped.value ||"
  '      _svcStopped\.value\r?\n          \? translate\("Service is not running"\)' = "      bind.isOutgoingOnly()`n          ? (_cadenaServidores.value == ''`n              ? 'Sem conexão com o servidor'`n              : _cadenaServidores.value == null`n                  ? 'Verificando servidores...'`n                  : '`${translate('Ready')} · `${_cadenaServidores.value}')`n          : _svcStopped.value`n          ? translate(`"Service is not running`")"
}
Trocar "$Fonte\flutter\lib\mobile\pages\server_page.dart" @{
  "return Row\(children: \[\r?\n          const Icon\(Icons\.check, color: colorPositive, size: iconSize\)\r?\n              \.marginOnly\(right: iconMarginRight\),\r?\n          Expanded\(child: Text\(translate\('Ready'\)\)\)\r?\n        \]\);" = "return FutureBuilder<String>(`n            // CadenaTech: nomes dos servidores que respondem; nenhum = sem conexao, em vermelho`n            future: bind.mainGetCommon(key: 'cadena-servidores'),`n            builder: (context, s) {`n              final semServidor = s.hasData && s.data!.isEmpty;`n              return Row(children: [`n                Icon(semServidor ? Icons.warning_amber_sharp : Icons.check,`n                        color: semServidor ? colorNegative : colorPositive,`n                        size: iconSize)`n                    .marginOnly(right: iconMarginRight),`n                Expanded(`n                    child: Text(semServidor`n                        ? 'Sem conexão com o servidor'`n                        : (s.hasData`n                            ? '`${translate('Ready')} · `${s.data}'`n                            : translate('Ready'))))`n              ]);`n            });"
}
# A gravacao avisa quando um arquivo comeca e termina. O aviso e uma funcao registrada pelo cadena_ftp, porque
# o libs/scrap nao enxerga o crate principal
Trocar "$Fonte\libs\scrap\src\common\record.rs" @{
  '#\[derive\(Debug, Clone\)\]\r?\npub struct RecorderContext2 \{' ="// CadenaTech: avisa (arquivo, concluida) quando uma gravacao comeca e quando termina. Registrado pelo cadena_ftp`npub static CADENA_AVISO: std::sync::OnceLock<fn(&str, bool)> = std::sync::OnceLock::new();`n`nfn cadena_avisar(arquivo: &str, concluida: bool) {`n    if let Some(f) = CADENA_AVISO.get() {`n        f(arquivo, concluida);`n    }`n}`n`n#[derive(Debug, Clone)]`npub struct RecorderContext2 {"
  'self\.send_state\(RecordState::NewFile\(ctx2\.filename\.clone\(\)\)\);' = "self.send_state(RecordState::NewFile(ctx2.filename.clone()));`n            cadena_avisar(&ctx2.filename, false);"
  'state = RecordState::RemoveFile;\r?\n        \}\r?\n        self\.ctx\.tx\.as_ref\(\)\.map\(\|tx\| tx\.send\(state\)\);\r?\n    \}' = "state = RecordState::RemoveFile;`n        }`n        self.ctx.tx.as_ref().map(|tx| tx.send(state));`n        cadena_avisar(&self.ctx2.filename, true);`n    }"
}
# O Tecnico so acessa depois de entrar com a conta da API (Configuracoes > Conta). A trava fica no
# programa: vale para conexoes pela tela, por atalho e pelo --connect
Trocar "$Fonte\src\client.rs" @{
  'debug_assert!\(peer == interface\.get_id\(\)\);' = "debug_assert!(peer == interface.get_id());`n        // CadenaTech: o Tecnico so acessa com a conta da API conectada (Configuracoes > Conta > Login)`n        if config::is_outgoing_only() && LocalConfig::get_option(`"access_token`").is_empty() {`n            bail!(`"$(Para-Rust $Marca.TextoLogin)`");`n        }`n        // CadenaTech: com o token de login o cliente exige a troca de chaves com o hbbs, que o hbbs aberto (sem -k)`n        // nao faz: `"Failed to secure tcp: deadline has elapsed`". O token so serve ao servidor Pro; a conta`n        // continua valendo na API (catalogo de enderecos) e na trava acima`n        let token = `"`";"
}
# Dois servidores automaticos (CADENA_SERVIDOR2 em common.rs): registro do Cliente nos dois, chave certa para cada
# servidor e segunda tentativa do Tecnico pelo servidor 2 (com o mecanismo id@servidor que o RustDesk ja tem)
Trocar "$Fonte\src\rendezvous_mediator.rs" @{
  'let servers = Config::get_rendezvous_servers\(\);\r?\n                SHOULD_EXIT\.store\(false' = "let servers = crate::common::cadena_servidores_registro();`n                SHOULD_EXIT.store(false"
  'let key = crate::get_key\(true\)\.await;\r?\n        crate::secure_tcp\(&mut conn, &key\)\.await\?;' = "let key = crate::common::cadena_chave_do_servidor(&host, crate::get_key(true).await);`n        crate::secure_tcp(&mut conn, &key).await?;"
  'let key = crate::get_key\(true\)\.await;\r?\n            if let Err\(err\) = crate::secure_tcp_required\(&mut socket, &key\)' = "let key = crate::common::cadena_chave_do_servidor(&self.host, crate::get_key(true).await);`n            if let Err(err) = crate::secure_tcp_required(&mut socket, &key)"
  'let key = crate::get_key\(true\)\.await;\r?\n                while let Some\(candidate\) = local_ice_rx' = "let key = crate::common::cadena_chave_do_servidor(&host, crate::get_key(true).await);`n                while let Some(candidate) = local_ice_rx"
  'crate::secure_tcp_required\(&mut socket, &crate::get_key\(true\)\.await\)\.await\?;' = "crate::secure_tcp_required(&mut socket, &crate::common::cadena_chave_do_servidor(&self.host, crate::get_key(true).await)).await?;"
}
Trocar "$Fonte\src\client.rs" @{
  'match Self::_start\(peer, key, token, conn_type, interface\.clone\(\)\)\.await \{' = "let mut resultado = Self::_start(peer, key, token, conn_type, interface.clone()).await;`n        // CadenaTech: o servidor 1 nao achou o ID ou nao respondeu; tenta o mesmo ID no servidor 2, com a chave dele`n        if resultado.is_err()`n            && !crate::common::CADENA_SERVIDOR2.is_empty()`n            && !peer.contains('@')`n            && interface.get_lch().read().unwrap().other_server.is_none()`n        {`n            log::info!(`"CadenaTech: tentando {} pelo servidor 2 ({})`", peer, crate::common::CADENA_SERVIDOR2);`n            crate::common::CADENA_TENTATIVA2.lock().unwrap().insert(`n                peer.to_owned(),`n                (`n                    peer.to_owned(),`n                    crate::common::CADENA_SERVIDOR2.to_owned(),`n                    crate::common::CADENA_CHAVE2.to_owned(),`n                ),`n            );`n            let segunda = Self::_start(peer, key, token, conn_type, interface.clone()).await;`n            crate::common::CADENA_TENTATIVA2.lock().unwrap().remove(peer);`n            if segunda.is_ok() {`n                resultado = segunda;`n            }`n        }`n        match resultado {"
  'let other_server = interface\.get_lch\(\)\.read\(\)\.unwrap\(\)\.other_server\.clone\(\);' = "let other_server = interface`n            .get_lch()`n            .read()`n            .unwrap()`n            .other_server`n            .clone()`n            .or_else(|| crate::common::CADENA_TENTATIVA2.lock().unwrap().get(peer).cloned());"
  'let mut conn = connect_tcp\(host\.clone\(\), CONNECT_TIMEOUT\)\.await\?;\r?\n    let key = crate::get_key\(true\)\.await;' = "let mut conn = connect_tcp(host.clone(), CONNECT_TIMEOUT).await?;`n    let key = crate::common::cadena_chave_do_servidor(&host, crate::get_key(true).await);"
}
# Interface antiga (Sciter), usada so pelo Cliente de 32 bits (x86_compilar.ps1): o essencial das telas do Flutter
#  - janela de aceitar: o aviso da marca (AvisoJanela) acima dos botoes;
#  - tela inicial: o texto do ID da marca (TextoId) e sem a senha no modo de aprovacao por clique;
#  - servico ligado sozinho ao abrir, como no Flutter (uma tentativa por abertura)
$CorAvisoTis = "#$((Hex $Marca.CorEscura).ToLower())"
Trocar "$Fonte\src\ui\cm.tis" @{
  '                <div style="size:\*"/>\r?\n                <div \.outer_buttons>' = "                <div style=`"size:*`"/>`n                {!auth && !disconnected && show_accept_btn && !c.is_file_transfer && !c.is_terminal && !c.port_forward ? <div style=`"background:$CorAvisoTis; color:white; padding:8px; margin-bottom:6px; border-radius:6px; font-size:0.9em;`">{`"$(Para-Tis $Marca.AvisoJanela)`"}</div> : `"`"}`n                <div .outer_buttons>"
}
Trocar "$Fonte\src\ui\index.tis" @{
  "\{outgoing_only \? translate\('outgoing_only_desk_tip'\) : translate\('desk_tip'\)\}" = "{outgoing_only ? translate('outgoing_only_desk_tip') : `"$(Para-Tis $Marca.TextoId)`"}"
  # Janela do Cliente (so recebe acesso): 180 px de largura deixava tudo espremido; 340 px e o visual da marca
  'const incoming_only_width = 180;' = 'const incoming_only_width = 340;'
  '\(handler\.is_installed\(\) \|\| disable_installation\) \? 300 : 390\)' = '(handler.is_installed() || disable_installation) ? 400 : 560)'
  'scaleIt\(incoming_only \? 390 : 600\)' = 'scaleIt(incoming_only ? ((handler.is_installed() || disable_installation) ? 420 : 600) : 600)'
  '            <div \.app>' = '            <div class={incoming_only ? "app cadena" : "app"}>'
  '\{!outgoing_only && <PasswordArea />\}' = "{!outgoing_only && handler.get_option('approve-mode') != 'click' && <PasswordArea />}"
  'function self\.ready\(\) \{' = "function self.ready() {`n    // CadenaTech: o Cliente liga o servico sozinho ao abrir (uma tentativa por abertura), como no Flutter`n    if (service_stopped && !outgoing_only) self.timer(2s, function() { handler.set_option(`"stop-service`", `"`"); });"
  # Titulo "Seu Computador": na janela estreita do Cliente ele quebra em duas linhas, e a altura fixa de uma linha
  # o fazia cobrir o texto de baixo
  '<div \.title style="flow:horizontal; position:relative; height:1\.6em; line-height:1\.6em">' = '<div .title style="flow:horizontal; position:relative; min-height:1.6em; line-height:1.25em">'
}
# Visual da janela do Cliente (classe "cadena" no .app, so no modo que so recebe acesso): titulo forte, texto
# arejado, o ID num cartao com a cor da marca e o aviso de instalar tambem na cor da marca
$CssCliente = @"
html {
    background-color: transparent;
}

/* CadenaTech: janela do Cliente */
.app.cadena .left-pane { padding-bottom: 64px; }
.app.cadena .left-pane > div:nth-child(1) { padding: 28px 30px 22px 30px; border-spacing: 18px; }
.app.cadena .title { font-size: 1.75em; font-weight: bold; color: color(text); }
.app.cadena .lighter-text { font-size: 1em; line-height: 1.5em; }
.app.cadena .your-desktop { border-left: $CorAvisoTis solid 5px; background: color(gray-bg); border-radius: 10px; padding: 14px 18px 16px 18px; border-spacing: 4px; }
.app.cadena .your-desktop > div { font-size: 0.85em; font-weight: bold; color: color(lighter-text); }
.app.cadena div#myid svg#menu { right: 0; }
.app.cadena .your-desktop input[type=text] { font-size: 2.2em; font-weight: bold; height: 1.35em; color: color(text); background: transparent; }
.app.cadena div.connect-status { padding: 14px 30px; }
.app.cadena div.install-me { background: $CorAvisoTis; border-radius: 10px; margin: 0 30px; padding: 16px 18px; }
.app.cadena div.install-me > div:nth-child(2) { font-size: 0.9em; line-height: 1.45em; }
"@
Trocar "$Fonte\src\ui\index.css" @{
  'html \{\r?\n    background-color: transparent;\r?\n\}' = ($CssCliente -replace "`r`n", "`n").TrimEnd("`n")
}
"Marca aplicada"
