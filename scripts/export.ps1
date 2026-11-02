<#
.SYNOPSIS
  Exports the canonical markdown outputs to editable Word and Excel files.
  No external dependencies (builds OOXML directly). Windows PowerShell 5.1.

.DESCRIPTION
  outputs/research-report.md   -> research-report.docx
  outputs/evidence-table.md    -> evidence-table.xlsx

  The exports are read-only copies: content is never altered, only converted.
  After writing, the script re-opens both files and checks that headings, tables,
  rows, DOIs and PMIDs match the markdown. Exit code 1 if any check fails.

  Gate: refuses to run unless -QcConfirmed is given (orchestrator confirms QC1-QC4
  passed) and the report is not marked "DRAFT - QC not completed". -AllowDraft is
  for testing only: it writes files named *.DRAFT.* .

.EXAMPLE
  powershell -File scripts\export.ps1 -QcConfirmed
#>
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$OutDir,
  [switch]$QcConfirmed,
  [switch]$AllowDraft
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8 = New-Object System.Text.UTF8Encoding($false)

$reportMd = Join-Path $Root 'outputs\research-report.md'
$tableMd = Join-Path $Root 'outputs\evidence-table.md'
if (-not $OutDir) { $OutDir = Join-Path $Root 'outputs' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

foreach ($f in @($reportMd, $tableMd)) {
  if (-not (Test-Path $f)) { throw "Missing input: $f" }
}
$reportText = [IO.File]::ReadAllText($reportMd, $utf8)
$tableText = [IO.File]::ReadAllText($tableMd, $utf8)

# ---- Gate ----
$isDraft = $reportText -match 'DRAFT - QC not completed'
if (-not $QcConfirmed -and -not $AllowDraft) {
  throw 'Export refused: pass -QcConfirmed only after QC1-QC4 have passed.'
}
if ($isDraft -and -not $AllowDraft) {
  throw 'Export refused: the report is marked "DRAFT - QC not completed".'
}
$suffix = ''
if ($AllowDraft) { $suffix = '.DRAFT' }
$docxPath = Join-Path $OutDir ('research-report' + $suffix + '.docx')
$xlsxPath = Join-Path $OutDir ('evidence-table' + $suffix + '.xlsx')

# ---- Helpers ----
function Esc([string]$s) { return [System.Security.SecurityElement]::Escape($s) }

function New-Zip([string]$path, $entries) {
  if (Test-Path $path) { Remove-Item $path -Force }
  $fs = [IO.File]::Open($path, [IO.FileMode]::Create)
  $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
  foreach ($name in $entries.Keys) {
    $e = $zip.CreateEntry($name)
    $sw = New-Object IO.StreamWriter($e.Open(), $utf8)
    $sw.Write([string]$entries[$name])
    $sw.Dispose()
  }
  $zip.Dispose()
  $fs.Dispose()
}

function Read-ZipEntry([string]$path, [string]$name) {
  $zip = [IO.Compression.ZipFile]::OpenRead($path)
  try {
    $e = $zip.GetEntry($name)
    if ($null -eq $e) { return $null }
    $sr = New-Object IO.StreamReader($e.Open(), $utf8)
    $t = $sr.ReadToEnd()
    $sr.Dispose()
    return $t
  } finally { $zip.Dispose() }
}

function Split-TableRow([string]$line) {
  $l = $line.Trim()
  if ($l.StartsWith('|')) { $l = $l.Substring(1) }
  if ($l.EndsWith('|')) { $l = $l.Substring(0, $l.Length - 1) }
  return [string[]]@(($l -split '\|') | ForEach-Object { $_.Trim() })
}

function Test-TableStart($lines, [int]$i) {
  return (($lines[$i] -match '^\s*\|') -and (($i + 1) -lt $lines.Count) -and ($lines[$i + 1] -match '^\s*\|?\s*:?-{2,}'))
}

# Returns ArrayList of string[] (header first, separator removed)
function Read-Table($lines, [int]$start) {
  $rows = New-Object System.Collections.ArrayList
  $j = $start
  while ($j -lt $lines.Count -and $lines[$j] -match '^\s*\|') {
    if ($j -ne ($start + 1)) { [void]$rows.Add((Split-TableRow $lines[$j])) }
    $j++
  }
  return , @{ rows = $rows; next = $j }
}

function Clean-Cell([string]$s) {
  $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)\s]+)\)', '$1 ($2)')
  $s = $s -replace '\*\*', ''
  $s = $s -replace '`', ''
  return $s
}

# ---- DOCX ----
$script:rels = New-Object System.Collections.ArrayList

function Add-Rel([string]$url) {
  $id = 'rIdL' + ($script:rels.Count + 1)
  [void]$script:rels.Add(@{ id = $id; url = $url })
  return $id
}

function New-Run([string]$t, [bool]$b, [bool]$i, [bool]$c, [string]$rid, [int]$sz) {
  if ($t -eq '') { return '' }
  $rp = ''
  if ($rid) { $rp += '<w:rStyle w:val="Hyperlink"/>' }
  if ($c) { $rp += '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>' }
  if ($b) { $rp += '<w:b/>' }
  if ($i) { $rp += '<w:i/>' }
  if ($sz -gt 0) { $rp += '<w:sz w:val="' + $sz + '"/>' }
  $run = '<w:r><w:rPr>' + $rp + '</w:rPr><w:t xml:space="preserve">' + (Esc $t) + '</w:t></w:r>'
  if ($rid) { $run = '<w:hyperlink r:id="' + $rid + '">' + $run + '</w:hyperlink>' }
  return $run
}

$inlineRx = [regex]'\*\*(?<b>.+?)\*\*|(?<![\*\w])\*(?<i>[^\*\s][^\*]*?)\*(?![\*\w])|`(?<c>[^`]+)`|\[(?<lt>[^\]]+)\]\((?<lu>[^)\s]+)\)|(?<u>https?://[^\s)\]|]+)'

function Convert-Inline([string]$text, [bool]$bold, [int]$sz) {
  $sb = New-Object System.Text.StringBuilder
  $pos = 0
  foreach ($m in $inlineRx.Matches($text)) {
    if ($m.Index -lt $pos) { continue }
    if ($m.Index -gt $pos) {
      [void]$sb.Append((New-Run $text.Substring($pos, $m.Index - $pos) $bold $false $false '' $sz))
    }
    $end = $m.Index + $m.Length
    if ($m.Groups['b'].Success) {
      [void]$sb.Append((New-Run $m.Groups['b'].Value $true $false $false '' $sz))
    } elseif ($m.Groups['i'].Success) {
      [void]$sb.Append((New-Run $m.Groups['i'].Value $bold $true $false '' $sz))
    } elseif ($m.Groups['c'].Success) {
      [void]$sb.Append((New-Run $m.Groups['c'].Value $bold $false $true '' $sz))
    } elseif ($m.Groups['lt'].Success) {
      $rid = Add-Rel $m.Groups['lu'].Value
      [void]$sb.Append((New-Run $m.Groups['lt'].Value $bold $false $false $rid $sz))
    } else {
      $u = $m.Groups['u'].Value
      $trim = $u.TrimEnd('.', ',', ';')
      $rid = Add-Rel $trim
      [void]$sb.Append((New-Run $trim $bold $false $false $rid $sz))
      $end = $m.Index + $trim.Length
    }
    $pos = $end
  }
  if ($pos -lt $text.Length) {
    [void]$sb.Append((New-Run $text.Substring($pos) $bold $false $false '' $sz))
  }
  return $sb.ToString()
}

function New-TableXml($rows) {
  $n = 0
  foreach ($r in $rows) { if ($r.Count -gt $n) { $n = $r.Count } }
  $w = [int](9600 / $n)
  $sz = 20
  if ($n -gt 6) { $sz = 16 }
  $x = New-Object System.Text.StringBuilder
  [void]$x.Append('<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders>')
  foreach ($side in 'top', 'left', 'bottom', 'right', 'insideH', 'insideV') {
    [void]$x.Append('<w:' + $side + ' w:val="single" w:sz="4" w:space="0" w:color="808080"/>')
  }
  [void]$x.Append('</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="80" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>')
  for ($k = 0; $k -lt $n; $k++) { [void]$x.Append('<w:gridCol w:w="' + $w + '"/>') }
  [void]$x.Append('</w:tblGrid>')
  for ($ri = 0; $ri -lt $rows.Count; $ri++) {
    $isHead = ($ri -eq 0)
    [void]$x.Append('<w:tr>')
    if ($isHead) { [void]$x.Append('<w:trPr><w:tblHeader/></w:trPr>') }
    for ($ci = 0; $ci -lt $n; $ci++) {
      $cell = ''
      if ($ci -lt $rows[$ri].Count) { $cell = $rows[$ri][$ci] }
      [void]$x.Append('<w:tc><w:tcPr><w:tcW w:w="' + $w + '" w:type="dxa"/>')
      if ($isHead) { [void]$x.Append('<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>') }
      [void]$x.Append('</w:tcPr><w:p><w:pPr><w:spacing w:after="40"/></w:pPr>')
      [void]$x.Append((Convert-Inline $cell $isHead $sz))
      [void]$x.Append('</w:p></w:tc>')
    }
    [void]$x.Append('</w:tr>')
  }
  [void]$x.Append('</w:tbl><w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>')
  return $x.ToString()
}

function Add-Paragraph($body, $para) {
  if ($para.Count -gt 0) {
    $text = ($para -join ' ')
    [void]$body.Append('<w:p>' + (Convert-Inline $text $false 0) + '</w:p>')
    $para.Clear()
  }
}

function Convert-MarkdownToBody([string[]]$lines) {
  $body = New-Object System.Text.StringBuilder
  $para = New-Object System.Collections.ArrayList
  $stats = @{ headings = 0; tables = 0; rows = 0 }
  $inCode = $false
  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]
    if ($line -match '^\s*```') {
      Add-Paragraph $body $para
      $inCode = -not $inCode
      $i++; continue
    }
    if ($inCode) {
      [void]$body.Append('<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>' + (New-Run $line $false $false $true '' 18) + '</w:p>')
      $i++; continue
    }
    if ($line -match '^\s*$') { Add-Paragraph $body $para; $i++; continue }
    if ($line -match '^\s*-{3,}\s*$') { Add-Paragraph $body $para; $i++; continue }
    if ($line -match '^(#{1,6})\s+(.*)$') {
      Add-Paragraph $body $para
      $lvl = [Math]::Min($Matches[1].Length, 4)
      [void]$body.Append('<w:p><w:pPr><w:pStyle w:val="Heading' + $lvl + '"/></w:pPr>' + (Convert-Inline $Matches[2] $false 0) + '</w:p>')
      $stats.headings++
      $i++; continue
    }
    if (Test-TableStart $lines $i) {
      Add-Paragraph $body $para
      $t = Read-Table $lines $i
      [void]$body.Append((New-TableXml $t.rows))
      $stats.tables++
      $stats.rows += $t.rows.Count
      $i = $t.next; continue
    }
    if ($line -match '^>\s?(.*)$') {
      Add-Paragraph $body $para
      [void]$body.Append('<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr>' + (Convert-Inline $Matches[1] $false 0) + '</w:p>')
      $i++; continue
    }
    if ($line -match '^(\s*)[-*]\s+(.*)$') {
      Add-Paragraph $body $para
      $level = [int]($Matches[1].Length / 2)
      $left = 720 + 360 * $level
      [void]$body.Append('<w:p><w:pPr><w:spacing w:after="60"/><w:ind w:left="' + $left + '" w:hanging="360"/></w:pPr>' +
        (New-Run ([string][char]0x2022) $false $false $false '' 0) + '<w:r><w:tab/></w:r>' + (Convert-Inline $Matches[2] $false 0) + '</w:p>')
      $i++; continue
    }
    if ($line -match '^(\s*)(\d+)\.\s+(.*)$') {
      Add-Paragraph $body $para
      $level = [int]($Matches[1].Length / 2)
      $left = 720 + 360 * $level
      [void]$body.Append('<w:p><w:pPr><w:spacing w:after="60"/><w:ind w:left="' + $left + '" w:hanging="360"/></w:pPr>' +
        (New-Run ($Matches[2] + '.') $false $false $false '' 0) + '<w:r><w:tab/></w:r>' + (Convert-Inline $Matches[3] $false 0) + '</w:p>')
      $i++; continue
    }
    [void]$para.Add($line.Trim())
    $i++
  }
  Add-Paragraph $body $para
  return @{ xml = $body.ToString(); stats = $stats }
}

$nsW = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
$nsR = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
$decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'

$reportLines = $reportText -split "\r?\n"
$conv = Convert-MarkdownToBody $reportLines
$docXml = $decl + '<w:document ' + $nsW + ' ' + $nsR + '><w:body>' + $conv.xml +
  '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr></w:body></w:document>'

function New-HeadingStyle([int]$n, [int]$size) {
  return '<w:style w:type="paragraph" w:styleId="Heading' + $n + '"><w:name w:val="heading ' + $n + '"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="100"/><w:outlineLvl w:val="' + ($n - 1) + '"/></w:pPr><w:rPr><w:b/><w:color w:val="1F3864"/><w:sz w:val="' + $size + '"/></w:rPr></w:style>'
}
$stylesXml = $decl + '<w:styles ' + $nsW + '><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>' +
  '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>' +
  (New-HeadingStyle 1 34) + (New-HeadingStyle 2 28) + (New-HeadingStyle 3 24) + (New-HeadingStyle 4 22) +
  '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:left="567"/></w:pPr><w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style>' +
  '<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style></w:styles>'

$relsXml = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
foreach ($r in $script:rels) {
  $relsXml += '<Relationship Id="' + $r.id + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="' + (Esc $r.url) + '" TargetMode="External"/>'
}
$relsXml += '</Relationships>'

$docxEntries = [ordered]@{}
$docxEntries['[Content_Types].xml'] = $decl + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>'
$docxEntries['_rels/.rels'] = $decl + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
$docxEntries['word/document.xml'] = $docXml
$docxEntries['word/styles.xml'] = $stylesXml
$docxEntries['word/_rels/document.xml.rels'] = $decl + $relsXml
New-Zip $docxPath $docxEntries

# ---- XLSX ----
function Get-ColName([int]$n) {
  $s = ''
  while ($n -gt 0) { $m = ($n - 1) % 26; $s = [char](65 + $m) + $s; $n = [int](($n - 1) / 26) }
  return $s
}

function New-SheetXml($rows, [bool]$filter) {
  $ncols = 0
  foreach ($r in $rows) { if ($r.Count -gt $ncols) { $ncols = $r.Count } }
  $widths = @()
  for ($c = 0; $c -lt $ncols; $c++) {
    $max = 8
    foreach ($r in $rows) { if ($c -lt $r.Count -and $r[$c].Length -gt $max) { $max = $r[$c].Length } }
    $widths += [Math]::Min([Math]::Max($max, 12), 60)
  }
  $x = New-Object System.Text.StringBuilder
  [void]$x.Append($decl + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>')
  for ($c = 0; $c -lt $ncols; $c++) {
    [void]$x.Append('<col min="' + ($c + 1) + '" max="' + ($c + 1) + '" width="' + $widths[$c] + '" customWidth="1"/>')
  }
  [void]$x.Append('</cols><sheetData>')
  for ($ri = 0; $ri -lt $rows.Count; $ri++) {
    [void]$x.Append('<row r="' + ($ri + 1) + '">')
    $style = 2
    if ($ri -eq 0) { $style = 1 }
    for ($c = 0; $c -lt $ncols; $c++) {
      $v = ''
      if ($c -lt $rows[$ri].Count) { $v = Clean-Cell $rows[$ri][$c] }
      [void]$x.Append('<c r="' + (Get-ColName ($c + 1)) + ($ri + 1) + '" s="' + $style + '" t="inlineStr"><is><t xml:space="preserve">' + (Esc $v) + '</t></is></c>')
    }
    [void]$x.Append('</row>')
  }
  [void]$x.Append('</sheetData>')
  if ($filter -and $rows.Count -gt 1) {
    [void]$x.Append('<autoFilter ref="A1:' + (Get-ColName $ncols) + $rows.Count + '"/>')
  }
  [void]$x.Append('</worksheet>')
  return $x.ToString()
}

$tableLines = $tableText -split "\r?\n"
$evRows = $null
for ($i = 0; $i -lt $tableLines.Count; $i++) {
  if (Test-TableStart $tableLines $i) { $evRows = (Read-Table $tableLines $i).rows; break }
}
if ($null -eq $evRows -or $evRows.Count -lt 2) { throw 'No evidence table (header plus at least one row) found in outputs/evidence-table.md' }

function Get-SectionBullets($lines, [string]$headingPattern) {
  $out = New-Object System.Collections.ArrayList
  $in = $false
  foreach ($l in $lines) {
    if ($l -match '^##\s') { $in = ($l -match $headingPattern); continue }
    if ($in -and $l -match '^\s*[-*]\s+(.*)$') { [void]$out.Add($Matches[1]) }
  }
  return , $out
}

$otherRows = New-Object System.Collections.ArrayList
[void]$otherRows.Add([string[]]@('Category', 'Record / criterion and reason'))
foreach ($b in (Get-SectionBullets $tableLines '^##\s+Excluded')) { [void]$otherRows.Add([string[]]@('Excluded', $b)) }
foreach ($b in (Get-SectionBullets $tableLines '^##\s+Uncertain')) { [void]$otherRows.Add([string[]]@('Uncertain (awaiting decision)', $b)) }

$qcStatus = 'QC1-QC4 confirmed by orchestrator'
if ($AllowDraft) { $qcStatus = 'DRAFT export for testing - QC not confirmed' }
$aboutRows = New-Object System.Collections.ArrayList
[void]$aboutRows.Add([string[]]@('Item', 'Value'))
[void]$aboutRows.Add([string[]]@('Generated', (Get-Date -Format 'yyyy-MM-dd HH:mm')))
[void]$aboutRows.Add([string[]]@('Source (canonical)', 'outputs/evidence-table.md'))
[void]$aboutRows.Add([string[]]@('Companion report', 'outputs/research-report.md'))
[void]$aboutRows.Add([string[]]@('QC status', $qcStatus))
[void]$aboutRows.Add([string[]]@('Studies in table', [string]($evRows.Count - 1)))
[void]$aboutRows.Add([string[]]@('Note', 'Read-only export of the markdown. Edit the markdown sources, not this file, to keep traceability to sources/records/.'))

$xlsxEntries = [ordered]@{}
$xlsxEntries['[Content_Types].xml'] = $decl + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
$xlsxEntries['_rels/.rels'] = $decl + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
$xlsxEntries['xl/workbook.xml'] = $decl + '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' + $nsR + '><sheets><sheet name="Evidence table" sheetId="1" r:id="rId1"/><sheet name="Excluded and uncertain" sheetId="2" r:id="rId2"/><sheet name="About" sheetId="3" r:id="rId3"/></sheets></workbook>'
$xlsxEntries['xl/_rels/workbook.xml.rels'] = $decl + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
$xlsxEntries['xl/styles.xml'] = $decl + '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9E2F3"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color auto="1"/></left><right style="thin"><color auto="1"/></right><top style="thin"><color auto="1"/></top><bottom style="thin"><color auto="1"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
$xlsxEntries['xl/worksheets/sheet1.xml'] = New-SheetXml $evRows $true
$xlsxEntries['xl/worksheets/sheet2.xml'] = New-SheetXml $otherRows $false
$xlsxEntries['xl/worksheets/sheet3.xml'] = New-SheetXml $aboutRows $false
New-Zip $xlsxPath $xlsxEntries

# ---- Verification (re-open the written files and compare with the markdown) ----
$checks = New-Object System.Collections.ArrayList
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
  [void]$checks.Add([pscustomobject]@{ Check = $name; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $detail })
}

$doiRx = [regex]'10\.\d{4,9}/[^\s\)\]\|,;"<>'']+'
function Get-Doi([string]$t) {
  return @($doiRx.Matches($t) | ForEach-Object { $_.Value.TrimEnd('.', ',', ';').ToLowerInvariant() } | Sort-Object -Unique)
}
function Get-Pmid([string]$t) {
  return @([regex]::Matches($t, 'PMID:?\s*(\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
function Same-Set($a, $b) {
  return ((@($a) -join ',') -eq (@($b) -join ','))
}

# docx
$dx = [xml](Read-ZipEntry $docxPath 'word/document.xml')
$nsm = New-Object System.Xml.XmlNamespaceManager($dx.NameTable)
$nsm.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
$dHeadings = $dx.SelectNodes('//w:pStyle[starts-with(@w:val,"Heading")]', $nsm).Count
$dTables = $dx.SelectNodes('//w:tbl', $nsm).Count
$dRows = $dx.SelectNodes('//w:tr', $nsm).Count
$dText = ($dx.SelectNodes('//w:t', $nsm) | ForEach-Object { $_.InnerText }) -join ' '
$dRelsText = Read-ZipEntry $docxPath 'word/_rels/document.xml.rels'
$dAll = $dText + ' ' + $dRelsText
Add-Check 'docx headings' ($dHeadings -eq $conv.stats.headings) ("md=$($conv.stats.headings) docx=$dHeadings")
Add-Check 'docx tables' ($dTables -eq $conv.stats.tables) ("md=$($conv.stats.tables) docx=$dTables")
Add-Check 'docx table rows' ($dRows -eq $conv.stats.rows) ("md=$($conv.stats.rows) docx=$dRows")
$mdDoi = Get-Doi $reportText; $dxDoi = Get-Doi $dAll
Add-Check 'docx DOIs identical' (Same-Set $mdDoi $dxDoi) ("md=$($mdDoi.Count) docx=$($dxDoi.Count)")
$mdPm = Get-Pmid $reportText; $dxPm = Get-Pmid $dText
Add-Check 'docx PMIDs identical' (Same-Set $mdPm $dxPm) ("md=$($mdPm.Count) docx=$($dxPm.Count)")

# xlsx
$sx = [xml](Read-ZipEntry $xlsxPath 'xl/worksheets/sheet1.xml')
$sns = New-Object System.Xml.XmlNamespaceManager($sx.NameTable)
$sns.AddNamespace('s', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
$xRows = $sx.SelectNodes('//s:sheetData/s:row', $sns).Count
Add-Check 'xlsx rows (header + studies)' ($xRows -eq $evRows.Count) ("md=$($evRows.Count) xlsx=$xRows")
$xText = ($sx.SelectNodes('//s:t', $sns) | ForEach-Object { $_.InnerText }) -join ' '
$mdTblDoi = Get-Doi $tableText; $xDoi = Get-Doi $xText
$mdTblPm = Get-Pmid ($tableText); $xPm = Get-Pmid $xText
Add-Check 'xlsx DOIs in table identical' (Same-Set (Get-Doi (($evRows | ForEach-Object { Clean-Cell ($_ -join ' ') }) -join ' ')) $xDoi) ("xlsx=$($xDoi.Count)")

# QC2 cross-check: table rows vs included records
$idCol = 0
$tableIds = @($evRows | Select-Object -Skip 1 | ForEach-Object { $_[$idCol] } | Sort-Object -Unique)
$recDir = Join-Path $Root 'sources\records'
$included = @()
if (Test-Path $recDir) {
  $included = @(Get-ChildItem $recDir -Filter *.md | Where-Object {
      (Get-Content -Raw -Encoding UTF8 $_.FullName) -match '(?m)^screening_status:\s*included\s*$'
    } | ForEach-Object { $_.BaseName } | Sort-Object -Unique)
}
Add-Check 'table ids = included records' (Same-Set $tableIds $included) ("table=$($tableIds.Count) included=$($included.Count)")

$checks | Format-Table -AutoSize | Out-String | Write-Host
Write-Host ('Written: ' + $docxPath)
Write-Host ('Written: ' + $xlsxPath)
if (@($checks | Where-Object { $_.Result -eq 'FAIL' }).Count -gt 0) {
  Write-Host 'One or more checks FAILED. Do not deliver these exports.'
  exit 1
}
Write-Host 'All export checks passed.'
