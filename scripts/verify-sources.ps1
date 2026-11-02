<#
.SYNOPSIS
  Independent audit of source records, the evidence table and the report citations.
  Read-only against the project; read-only GET requests to doi.org, Crossref,
  NCBI E-utilities and non-DOI/non-PubMed source URLs. Windows PowerShell 5.1.

.DESCRIPTION
  Per record in sources/records:
    required fields, DOI format, DOI resolves (doi.org handle API), Crossref
    metadata (title, year, journal, retraction/update notices), PubMed metadata
    (title, authors, year, journal, DOI in PubMed, retraction publication types),
    URL consistency (URL contains the record's DOI/PMID) and URL reachability
    for other hosts.
  Across the project:
    evidence-table rows vs records, report References vs records, in-text PMIDs
    vs References, and numeric trace (every number in the report body must occur
    in the evidence table or a record).

  Writes outputs/audit-report.md. Exit code 1 if any FAIL.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-sources.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-sources.ps1 -Scope Included
#>
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [ValidateSet('All', 'Included')][string]$Scope = 'All',
  [string]$OutFile,
  [switch]$SkipNetwork
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (-not $OutFile) { $OutFile = Join-Path $Root 'outputs\audit-report.md' }
$ua = @{ 'User-Agent' = 'evidence-audit/1.0 (research QC script)' }

# Pattern for common mojibake sequences, built from code points so this file stays ASCII-only:
# Hebrew gimel + per-mille sign, A-tilde, a-circumflex + euro sign, replacement character.
$mojibakeRx = ([string][char]0x05D2 + [char]0x2030) + '|' + [char]0x00C3 + '|' + ([string][char]0x00E2 + [char]0x20AC) + '|' + [char]0xFFFD

$findings = New-Object System.Collections.ArrayList
function Add-Finding([string]$rec, [string]$check, [string]$status, [string]$detail) {
  [void]$findings.Add([pscustomobject]@{ Record = $rec; Check = $check; Status = $status; Detail = $detail })
}

# ---------- text helpers ----------
function Normalize-Text([string]$s) {
  if (-not $s) { return '' }
  $s = [System.Web.HttpUtility]::HtmlDecode($s)
  $s = [regex]::Replace($s, '<[^>]+>', ' ')
  $s = $s.Replace('&', ' and ')
  $s = $s.ToLowerInvariant()
  $s = [regex]::Replace($s, '[^\p{L}\p{N}]+', ' ')
  return $s.Trim()
}
function Token-Similarity([string]$a, [string]$b) {
  $ta = @((Normalize-Text $a) -split ' ' | Where-Object { $_ } | Sort-Object -Unique)
  $tb = @((Normalize-Text $b) -split ' ' | Where-Object { $_ } | Sort-Object -Unique)
  if ($ta.Count -eq 0 -or $tb.Count -eq 0) { return 0.0 }
  $inter = @($ta | Where-Object { $tb -contains $_ }).Count
  $union = @($ta + $tb | Sort-Object -Unique).Count
  return [double]$inter / [double]$union
}
function Compare-Title([string]$rec, [string]$id, [string]$mine, [string]$theirs, [string]$source) {
  $sim = Token-Similarity $mine $theirs
  $s = [Math]::Round($sim, 2)
  if ($sim -ge 0.9) { Add-Finding $rec "title vs $source" 'PASS' "similarity $s" }
  elseif ($sim -ge 0.6) { Add-Finding $rec "title vs $source" 'WARN' "similarity $s; record: '$mine' | $source`: '$theirs'" }
  else { Add-Finding $rec "title vs $source" 'FAIL' "similarity $s; record: '$mine' | $source`: '$theirs'" }
}
function Compare-Journal([string]$rec, [string]$mine, [string[]]$theirs, [string]$source) {
  $mineClean = ($mine -replace '\(.*?\)', '') -replace ',.*$', ''
  $m = Normalize-Text $mineClean
  $ok = $false
  foreach ($t in $theirs) {
    $n = Normalize-Text $t
    if ($n -and $m -and ($n -eq $m -or $n.Contains($m) -or $m.Contains($n))) { $ok = $true }
  }
  if ($ok) { Add-Finding $rec "journal vs $source" 'PASS' $mine }
  else { Add-Finding $rec "journal vs $source" 'WARN' ("record: '$mine' | ${source}: '" + ($theirs -join "' / '") + "'") }
}

# ---------- network helpers ----------
function Invoke-Json([string]$url) {
  $last = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      return @{ ok = $true; data = (Invoke-RestMethod -Uri $url -Headers $ua -TimeoutSec 30) }
    } catch {
      $code = 0
      if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
      $last = @{ ok = $false; code = $code; err = $_.Exception.Message }
      if ($code -eq 429 -or $code -ge 500) { Start-Sleep -Seconds (2 * $attempt) } else { break }
    }
  }
  return $last
}
function Escape-Doi([string]$doi) {
  return ([uri]::EscapeUriString($doi)).Replace('#', '%23').Replace('?', '%3F')
}
function Test-UrlReachable([string]$url) {
  try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5 -Headers $ua
    return @{ code = [int]$resp.StatusCode; err = '' }
  } catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    return @{ code = $code; err = $_.Exception.Message }
  }
}

# ---------- parse records ----------
$recDir = Join-Path $Root 'sources\records'
if (-not (Test-Path $recDir)) { throw "No records folder: $recDir" }
$doiRx = [regex]'10\.\d{4,9}/[^\s\)\]\|,;"<>'']+'
$records = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem $recDir -Filter *.md | Sort-Object Name)) {
  $text = [IO.File]::ReadAllText($f.FullName, $utf8)
  $fields = @{}
  foreach ($line in ($text -split "\r?\n")) {
    if ($line -match '^\s*-\s+\*\*(?<k>[^*:]+):\*\*\s*(?<v>.*)$') {
      $k = $Matches['k'].Trim()
      if (-not $fields.ContainsKey($k)) { $fields[$k] = $Matches['v'].Trim() }
    }
  }
  $title = ''
  if ($text -match '(?m)^#\s+(.+)$') { $title = $Matches[1].Trim() }
  $ver = ''; if ($text -match '(?m)^verification_status:\s*(.+?)\s*$') { $ver = $Matches[1] }
  $scr = ''; if ($text -match '(?m)^screening_status:\s*(.+?)\s*$') { $scr = $Matches[1] }
  $doi = ''
  if ($fields.ContainsKey('DOI')) {
    $dm = $doiRx.Match($fields['DOI'])
    if ($dm.Success) { $doi = $dm.Value.TrimEnd('.', ',', ';') }
  }
  $pmid = ''
  foreach ($k in $fields.Keys) {
    if ($k -like 'PMID*') { $pmMatch = [regex]::Match($fields[$k], '\b(\d{6,9})\b'); if ($pmMatch.Success) { $pmid = $pmMatch.Groups[1].Value } }
  }
  if (-not $pmid -and $f.BaseName -match '^pmid-(\d+)$') { $pmid = $Matches[1] }
  $year = ''
  if ($fields.ContainsKey('Publication year')) { $ym = [regex]::Match($fields['Publication year'], '\b(19|20)\d{2}\b'); if ($ym.Success) { $year = $ym.Value } }
  $urls = @()
  if ($fields.ContainsKey('Source URL')) { $urls = @([regex]::Matches($fields['Source URL'], 'https?://[^\s;)\]]+') | ForEach-Object { $_.Value.TrimEnd('.', ',') }) }
  $authors = ''; if ($fields.ContainsKey('Authors')) { $authors = $fields['Authors'] }
  $journal = ''; if ($fields.ContainsKey('Journal')) { $journal = $fields['Journal'] }
  [void]$records.Add([pscustomobject]@{
      Id = $f.BaseName; Path = $f.FullName; Title = $title; Journal = $journal; Year = $year; Authors = $authors
      Doi = $doi; Pmid = $pmid; Urls = $urls; Verification = $ver; Screening = $scr; Text = $text
    })
}
if ($Scope -eq 'Included') { $records = @($records | Where-Object { $_.Screening -eq 'included' }) }
Write-Host ("Records to audit: " + @($records).Count + " (scope $Scope)")

# ---------- batch PubMed lookup ----------
$pm = @{}
if (-not $SkipNetwork) {
  $ids = @($records | Where-Object { $_.Pmid } | ForEach-Object { $_.Pmid } | Sort-Object -Unique)
  for ($i = 0; $i -lt $ids.Count; $i += 100) {
    $chunk = $ids[$i..([Math]::Min($i + 99, $ids.Count - 1))] -join ','
    $res = Invoke-Json ("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id=" + $chunk)
    if ($res.ok) {
      foreach ($uid in $res.data.result.uids) { $pm[$uid] = $res.data.result.PSObject.Properties[$uid].Value }
    } else {
      Write-Host ("esummary failed: " + $res.err)
    }
    Start-Sleep -Milliseconds 400
  }
}

# ---------- per-record checks ----------
$n = 0
foreach ($rec in $records) {
  $n++
  $id = $rec.Id
  Write-Host ("[{0}/{1}] {2}" -f $n, @($records).Count, $id)

  # required fields
  $missing = @()
  if (-not $rec.Title) { $missing += 'title' }
  if (-not $rec.Authors -or $rec.Authors -match 'not (available|retrieved)') { $missing += 'authors' }
  if (-not $rec.Journal) { $missing += 'journal' }
  if (-not $rec.Year) { $missing += 'year' }
  if (-not $rec.Doi -and -not $rec.Pmid) { $missing += 'DOI or PMID' }
  if (@($rec.Urls).Count -eq 0) { $missing += 'source URL' }
  if ($missing.Count -gt 0) { Add-Finding $id 'required fields' 'FAIL' ('missing: ' + ($missing -join ', ')) }
  else { Add-Finding $id 'required fields' 'PASS' 'all present' }
  if ($rec.Verification -ne 'verified') { Add-Finding $id 'verification_status' 'WARN' ("status is '" + $rec.Verification + "'") }

  # mojibake / encoding damage
  if ($rec.Text -match $mojibakeRx) { Add-Finding $id 'text encoding' 'WARN' 'possible corrupted characters in record text (check abstract/extracted numbers)' }

  # DOI format
  if ($rec.Doi) {
    if ($rec.Doi -match '^10\.\d{4,9}/\S+$') { Add-Finding $id 'DOI format' 'PASS' $rec.Doi }
    else { Add-Finding $id 'DOI format' 'FAIL' $rec.Doi }
  }

  # URL consistency (offline)
  foreach ($u in $rec.Urls) {
    if ($u -match 'pubmed\.ncbi\.nlm\.nih\.gov/(\d+)') {
      if ($Matches[1] -eq $rec.Pmid) { Add-Finding $id "URL $u" 'PASS' 'PMID matches record' }
      else { Add-Finding $id "URL $u" 'FAIL' ("URL PMID " + $Matches[1] + " differs from record PMID '" + $rec.Pmid + "'") }
    } elseif ($u -match 'doi\.org/(10\..+)$') {
      if ($rec.Doi -and ([uri]::UnescapeDataString($Matches[1]).ToLowerInvariant() -eq $rec.Doi.ToLowerInvariant())) { Add-Finding $id "URL $u" 'PASS' 'DOI matches record' }
      else { Add-Finding $id "URL $u" 'FAIL' ("URL DOI differs from record DOI '" + $rec.Doi + "'") }
    }
  }

  if ($SkipNetwork) { continue }

  # DOI resolves
  if ($rec.Doi) {
    $h = Invoke-Json ("https://doi.org/api/handles/" + (Escape-Doi $rec.Doi))
    if ($h.ok -and $h.data.responseCode -eq 1) { Add-Finding $id 'DOI resolves (doi.org)' 'PASS' 'handle exists' }
    elseif ($h.ok) { Add-Finding $id 'DOI resolves (doi.org)' 'FAIL' ("responseCode " + $h.data.responseCode) }
    elseif ($h.code -eq 404) { Add-Finding $id 'DOI resolves (doi.org)' 'FAIL' 'DOI not found (404)' }
    else { Add-Finding $id 'DOI resolves (doi.org)' 'WARN' ("lookup failed: " + $h.err) }

    $cr = Invoke-Json ("https://api.crossref.org/works/" + (Escape-Doi $rec.Doi))
    Start-Sleep -Milliseconds 150
    if ($cr.ok) {
      $msg = $cr.data.message
      $crTitle = ''; if ($msg.title) { $crTitle = [string]$msg.title[0] }
      Compare-Title $id $id $rec.Title $crTitle 'Crossref'
      $years = New-Object System.Collections.ArrayList
      foreach ($pn in 'issued', 'published-online', 'published-print', 'published') {
        $d = $msg.$pn
        if ($d -and $d.'date-parts' -and $d.'date-parts'[0] -and $d.'date-parts'[0][0]) { [void]$years.Add([string]$d.'date-parts'[0][0]) }
      }
      if ($years -contains $rec.Year) { Add-Finding $id 'year vs Crossref' 'PASS' $rec.Year }
      else { Add-Finding $id 'year vs Crossref' 'WARN' ("record " + $rec.Year + " | Crossref " + (($years | Sort-Object -Unique) -join ', ')) }
      Compare-Journal $id $rec.Journal @($msg.'container-title') 'Crossref'
      $notices = @()
      foreach ($prop in 'updated-by', 'update-to') {
        $items = $msg.$prop
        if ($items) { foreach ($it in $items) { $notices += ("" + $it.type + " (" + $it.DOI + ")") } }
      }
      if ($notices.Count -gt 0) { Add-Finding $id 'Crossref notices' 'WARN' ('update/correction/retraction notices: ' + ($notices -join '; ')) }
      else { Add-Finding $id 'Crossref notices' 'PASS' 'none' }
    } elseif ($cr.code -eq 404) { Add-Finding $id 'Crossref lookup' 'WARN' 'DOI not in Crossref (may be registered elsewhere)' }
    else { Add-Finding $id 'Crossref lookup' 'WARN' ("failed: " + $cr.err) }
  }

  # PubMed
  if ($rec.Pmid) {
    if ($pm.ContainsKey($rec.Pmid)) {
      $p = $pm[$rec.Pmid]
      Compare-Title $id $id $rec.Title ([string]$p.title) 'PubMed'
      $pyear = ''; if ($p.pubdate -match '\b((19|20)\d{2})\b') { $pyear = $Matches[1] }
      $eyear = ''; if ($p.epubdate -match '\b((19|20)\d{2})\b') { $eyear = $Matches[1] }
      if ($rec.Year -eq $pyear -or $rec.Year -eq $eyear) { Add-Finding $id 'year vs PubMed' 'PASS' $rec.Year }
      else { Add-Finding $id 'year vs PubMed' 'WARN' ("record " + $rec.Year + " | PubMed pubdate '" + $p.pubdate + "' epub '" + $p.epubdate + "'") }
      Compare-Journal $id $rec.Journal @([string]$p.fulljournalname, [string]$p.source) 'PubMed'
      $pmAuthors = @($p.authors | ForEach-Object { $_.name })
      $authorsClean = [regex]::Replace($rec.Authors, '\([^)]*\)?', '')
      $recAuthors = @(($authorsClean -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch 'authors' })
      if ($pmAuthors.Count -gt 0 -and $recAuthors.Count -gt 0) {
        if ((Normalize-Text $pmAuthors[0]) -ne (Normalize-Text $recAuthors[0])) { Add-Finding $id 'first author vs PubMed' 'FAIL' ("record '" + $recAuthors[0] + "' | PubMed '" + $pmAuthors[0] + "'") }
        elseif ($pmAuthors.Count -eq $recAuthors.Count -and (Normalize-Text $pmAuthors[-1]) -ne (Normalize-Text $recAuthors[-1])) { Add-Finding $id 'authors vs PubMed' 'WARN' ("last author differs: record '" + $recAuthors[-1] + "' | PubMed '" + $pmAuthors[-1] + "'") }
        elseif ($recAuthors.Count -lt $pmAuthors.Count) { Add-Finding $id 'authors vs PubMed' 'PASS' ("first author matches; record lists $($recAuthors.Count) of $($pmAuthors.Count) authors (truncated list)") }
        elseif ($pmAuthors.Count -ne $recAuthors.Count) { Add-Finding $id 'authors vs PubMed' 'WARN' ("author count record " + $recAuthors.Count + " | PubMed " + $pmAuthors.Count) }
        else { Add-Finding $id 'authors vs PubMed' 'PASS' ("$($recAuthors.Count) authors match") }
      }
      $pmDoi = ''
      foreach ($a in $p.articleids) { if ($a.idtype -eq 'doi') { $pmDoi = [string]$a.value } }
      if ($rec.Doi -and $pmDoi) {
        if ($pmDoi.ToLowerInvariant() -eq $rec.Doi.ToLowerInvariant()) { Add-Finding $id 'DOI vs PubMed' 'PASS' 'same DOI in PubMed' }
        else { Add-Finding $id 'DOI vs PubMed' 'FAIL' ("record " + $rec.Doi + " | PubMed " + $pmDoi) }
      } elseif ($rec.Doi -and -not $pmDoi) { Add-Finding $id 'DOI vs PubMed' 'WARN' 'PubMed lists no DOI for this PMID' }
      $badTypes = @($p.pubtype | Where-Object { $_ -match 'Retract|Withdraw|Erratum|Correction|Expression of Concern' })
      if ($badTypes.Count -gt 0) { Add-Finding $id 'PubMed notices' 'WARN' ('publication types: ' + ($badTypes -join '; ')) }
      else { Add-Finding $id 'PubMed notices' 'PASS' 'no retraction or correction type' }
    } else {
      Add-Finding $id 'PMID resolves (PubMed)' 'FAIL' ("PMID " + $rec.Pmid + " not returned by PubMed")
    }
  }

  # other URLs reachable
  foreach ($u in $rec.Urls) {
    if ($u -match 'pubmed\.ncbi\.nlm\.nih\.gov|doi\.org|api\.crossref\.org') { continue }
    $t = Test-UrlReachable $u
    if ($t.code -ge 200 -and $t.code -lt 300) { Add-Finding $id "URL reachable $u" 'PASS' ("HTTP " + $t.code) }
    elseif ($t.code -in 404, 410) { Add-Finding $id "URL reachable $u" 'FAIL' ("HTTP " + $t.code) }
    else { Add-Finding $id "URL reachable $u" 'WARN' ("HTTP " + $t.code + " " + $t.err) }
  }
}

# ---------- evidence table vs records ----------
$tablePath = Join-Path $Root 'outputs\evidence-table.md'
$tableText = ''
$byId = @{}; foreach ($rec in $records) { $byId[$rec.Id] = $rec }
$allRecordsText = ($records | ForEach-Object { $_.Text }) -join "`n"
if (Test-Path $tablePath) {
  $tableText = [IO.File]::ReadAllText($tablePath, $utf8)
  $tl = $tableText -split "\r?\n"
  $rows = @()
  for ($i = 0; $i -lt $tl.Count - 1; $i++) {
    if ($tl[$i] -match '^\s*\|' -and $tl[$i + 1] -match '^\s*\|?\s*:?-{2,}') {
      $hdrCells = @(($tl[$i].Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
      $j = $i + 2
      while ($j -lt $tl.Count -and $tl[$j] -match '^\s*\|') { $rows += $tl[$j]; $j++ }
      break
    }
  }
  $tableIds = @()
  foreach ($row in $rows) {
    $cells = @(($row.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
    $rid = $cells[0]; $tableIds += $rid
    if (-not $byId.ContainsKey($rid)) { Add-Finding "table:$rid" 'table row has record' 'FAIL' 'no matching file in sources/records'; continue }
    $rec = $byId[$rid]
    if ($rec.Screening -ne 'included') { Add-Finding "table:$rid" 'table row is included' 'FAIL' ("record screening_status is '" + $rec.Screening + "'") } else { Add-Finding "table:$rid" 'table row is included' 'PASS' 'included' }
    if ($rec.Verification -ne 'verified') { Add-Finding "table:$rid" 'table row is verified' 'FAIL' ("record verification_status is '" + $rec.Verification + "'") }
    $rowText = $row
    if ($rec.Doi -and -not $rowText.Contains($rec.Doi)) { Add-Finding "table:$rid" 'table DOI' 'FAIL' ("row does not contain record DOI " + $rec.Doi) }
    elseif ($rec.Doi) { Add-Finding "table:$rid" 'table DOI' 'PASS' $rec.Doi }
    if ($rec.Pmid -and -not $rowText.Contains($rec.Pmid)) { Add-Finding "table:$rid" 'table PMID' 'FAIL' ("row does not contain record PMID " + $rec.Pmid) }
    # access level in the record must agree with the table's basis column
    $basisIdx = [array]::IndexOf($hdrCells, 'basis')
    $accessM = [regex]::Match($rec.Text, '\*\*Access level seen:\*\*\s*(.+)')
    if ($basisIdx -ge 0 -and $basisIdx -lt $cells.Count -and $accessM.Success) {
      $basis = $cells[$basisIdx].ToLowerInvariant(); $access = $accessM.Groups[1].Value.ToLowerInvariant()
      if ($basis -match 'full text' -and $access -match 'abstract only' -and $access -notmatch 'full text') { Add-Finding "table:$rid" 'access level vs basis' 'FAIL' ("table basis is '" + $cells[$basisIdx] + "' but record says '" + $accessM.Groups[1].Value.Trim() + "'") }
      elseif ($basis -match 'abstract' -and $access -match 'full text' -and $access -notmatch 'abstract only') { Add-Finding "table:$rid" 'access level vs basis' 'FAIL' ("table basis is '" + $cells[$basisIdx] + "' but record says '" + $accessM.Groups[1].Value.Trim() + "'") }
      else { Add-Finding "table:$rid" 'access level vs basis' 'PASS' $cells[$basisIdx] }
    }
    # every number in the row must occur in the record (no agent-computed values)
    $recNoComma = $rec.Text -replace '(?<=\d),(?=\d{3})', ''
    $rowMissing = @()
    foreach ($nm in ([regex]::Matches(($rowText -replace 'https?://\S+|10\.\d{4,9}/\S+', ' '), '(?<![\w.])(\d{1,3}(,\d{3})+|\d+\.\d+|\d+%)(?![\w])') | ForEach-Object { $_.Value } | Sort-Object -Unique)) {
      $plainNm = $nm -replace ',', ''
      if (-not ($rec.Text.Contains($nm) -or $recNoComma.Contains($plainNm))) { $rowMissing += $nm }
    }
    if ($rowMissing.Count -gt 0) { Add-Finding "table:$rid" 'table numbers in record' 'WARN' ('numbers in table row not found in the record (agent-computed or mistyped?): ' + ($rowMissing -join ', ')) }
  }
  foreach ($rec in ($records | Where-Object { $_.Screening -eq 'included' })) {
    if ($tableIds -notcontains $rec.Id) { Add-Finding "table:$($rec.Id)" 'included record has table row' 'FAIL' 'included record missing from evidence table' }
  }
} else {
  Add-Finding 'evidence-table' 'file exists' 'WARN' 'outputs/evidence-table.md not found'
}

# ---------- report citations ----------
$reportPath = Join-Path $Root 'outputs\research-report.md'
$unmatched = @()
if (Test-Path $reportPath) {
  $rep = [IO.File]::ReadAllText($reportPath, $utf8)
  $repLines = $rep -split "\r?\n"
  $refStart = -1
  for ($i = 0; $i -lt $repLines.Count; $i++) { if ($repLines[$i] -match '^#{1,3}\s.*References') { $refStart = $i } }
  if ($refStart -lt 0) { Add-Finding 'report' 'References section' 'FAIL' 'no References heading found' }
  else {
    $refLines = @($repLines[($refStart + 1)..($repLines.Count - 1)] | Where-Object { $_ -match '^\s*\d+\.\s+' })
    $body = ($repLines[0..($refStart - 1)]) -join "`n"
    $refPmids = @()
    foreach ($ref in $refLines) {
      $pmM = [regex]::Match($ref, 'PMID:?\s*(\d{6,9})')
      $label = 'ref ' + ([regex]::Match($ref, '^\s*(\d+)\.').Groups[1].Value)
      if (-not $pmM.Success) {
        $recM = [regex]::Match($ref, 'records/(pmid-\d+)')
        if (-not $recM.Success) { Add-Finding "report:$label" 'reference identifiable' 'FAIL' 'no PMID or record path in reference'; continue }
        $key = $recM.Groups[1].Value
      } else { $key = 'pmid-' + $pmM.Groups[1].Value; $refPmids += $pmM.Groups[1].Value }
      if (-not $byId.ContainsKey($key)) { Add-Finding "report:$label" 'reference has record' 'FAIL' "no record $key"; continue }
      $rec = $byId[$key]
      if ($rec.Screening -ne 'included') { Add-Finding "report:$label" 'reference is included study' 'FAIL' ("$key screening_status is '" + $rec.Screening + "'") }
      $dm = $doiRx.Match($ref)
      if ($rec.Doi) {
        if ($dm.Success -and ($dm.Value.TrimEnd('.', ',', ';').ToLowerInvariant() -eq $rec.Doi.ToLowerInvariant())) { Add-Finding "report:$label" 'reference DOI' 'PASS' $rec.Doi }
        else { Add-Finding "report:$label" 'reference DOI' 'FAIL' ("reference DOI differs from record " + $rec.Doi) }
      }
      $nref = Normalize-Text $ref
      if (-not $nref.Contains((Normalize-Text $rec.Title))) { Add-Finding "report:$label" 'reference title' 'FAIL' 'title text in reference differs from record title' }
      $journalClean = ($rec.Journal -replace '\(.*?\)', '') -replace ',.*$', ''
      $journalAbbr = ''
      $am = [regex]::Match($rec.Journal, '\(([^)]+)\)')
      if ($am.Success) { $journalAbbr = Normalize-Text $am.Groups[1].Value }
      $journalFound = $nref.Contains((Normalize-Text $journalClean)) -or ($journalAbbr -and $nref.Contains($journalAbbr))
      if ($rec.Journal -and -not $journalFound) { Add-Finding "report:$label" 'reference journal' 'WARN' ("journal '" + $rec.Journal + "' not found in reference") }
      if ($rec.Year -and $ref -notmatch [regex]::Escape($rec.Year)) { Add-Finding "report:$label" 'reference year' 'FAIL' ("year " + $rec.Year + " not in reference") }
      $first = ''; if ($rec.Authors) { $first = (($rec.Authors -split ';')[0]).Trim().Split(' ')[0] }
      if ($first -and $ref -notmatch [regex]::Escape($first)) { Add-Finding "report:$label" 'reference first author' 'FAIL' ("first author '$first' not in reference") }
      if (-not $rec.Urls -or -not ($ref -match 'https?://')) { Add-Finding "report:$label" 'reference link' 'WARN' 'no link in reference' }
    }
    # in-text citations vs references
    $bodyPmids = @()
    foreach ($m in [regex]::Matches($body, 'PMID:?\s*(\d{6,9})')) { $bodyPmids += $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($body, '\((\d{7,9})\)')) { $bodyPmids += $m.Groups[1].Value }
    $slugPmids = @()
    foreach ($m in [regex]::Matches($body, 'pmid-(\d{6,9})')) { $slugPmids += $m.Groups[1].Value }
    $bodyPmids = @($bodyPmids | Sort-Object -Unique)
    $slugPmids = @($slugPmids | Sort-Object -Unique)
    foreach ($b in $bodyPmids) {
      if ($refPmids -contains $b) { continue }
      $key = 'pmid-' + $b
      if (-not $byId.ContainsKey($key)) { Add-Finding "report:PMID $b" 'cited study in References' 'FAIL' 'PMID in text has no record and is not in References' }
      elseif ($byId[$key].Screening -eq 'included') { Add-Finding "report:PMID $b" 'cited study in References' 'FAIL' 'included study cited in text but missing from References' }
      else { Add-Finding "report:PMID $b" 'record mentioned in body' 'WARN' ("record is '" + $byId[$key].Screening + "' and not in References; fine if listed only in the screening flow, not if used as evidence") }
    }
    foreach ($b in $slugPmids) {
      if ($refPmids -notcontains $b -and $bodyPmids -notcontains $b) { Add-Finding "report:pmid-$b" 'record mentioned in body' 'WARN' 'record id mentioned in the body but not in References (check it is not used as evidence)' }
    }
    foreach ($r2 in ($refPmids | Sort-Object -Unique)) {
      if ($bodyPmids -notcontains $r2) { Add-Finding "report:PMID $r2" 'reference cited in text' 'WARN' 'in References but never cited in the body by PMID' }
    }
    Add-Finding 'report' 'citation counts' 'PASS' ("references=" + $refLines.Count + ", distinct PMIDs cited in body=" + $bodyPmids.Count)

    # numeric trace
    $source = $tableText + "`n" + $allRecordsText
    $sourceNoComma = $source -replace '(?<=\d),(?=\d{3})', ''
    $bodyForNums = (($body -split "\r?\n") | Where-Object { $_ -notmatch '^#' }) -join "`n"
    $bodyForNums = [regex]::Replace($bodyForNums, 'PMID:?\s*\d+|pmid-\d+|\(\d{7,9}\)|https?://\S+|\b(19|20)\d{2}-\d{2}-\d{2}\b|\b10\.\d{4,9}/\S+', ' ')
    $numRx = [regex]'(?<![\w.])(\d{1,3}(,\d{3})+|\d+\.\d+|\d+%)(?![\w])'
    $nums = @($numRx.Matches($bodyForNums) | ForEach-Object { $_.Value } | Sort-Object -Unique)
    foreach ($num in $nums) {
      $plain = $num -replace ',', ''
      if (-not ($source.Contains($num) -or $sourceNoComma.Contains($plain))) { $unmatched += $num }
    }
    if ($unmatched.Count -gt 0) { Add-Finding 'report' 'numeric trace' 'WARN' ("numbers in report body not found in evidence table or records (review by hand): " + ($unmatched -join ', ')) }
    else { Add-Finding 'report' 'numeric trace' 'PASS' ("$($nums.Count) distinct numbers all found in the evidence table or records") }
  }
} else {
  Add-Finding 'report' 'file exists' 'WARN' 'outputs/research-report.md not found'
}

# ---------- write report ----------
$fail = @($findings | Where-Object { $_.Status -eq 'FAIL' })
$warn = @($findings | Where-Object { $_.Status -eq 'WARN' })
$pass = @($findings | Where-Object { $_.Status -eq 'PASS' })
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Audit report')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by scripts/verify-sources.ps1 | scope: $Scope | network: $(if ($SkipNetwork) { 'skipped' } else { 'doi.org, Crossref, NCBI E-utilities' })")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("**Result:** $($fail.Count) FAIL, $($warn.Count) WARN, $($pass.Count) PASS across $(@($records).Count) records.")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Per record')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Record | Screening | Worst | FAIL | WARN |')
[void]$sb.AppendLine('|---|---|---|---|---|')
foreach ($rec in $records) {
  $rf = @($findings | Where-Object { $_.Record -eq $rec.Id })
  $f1 = @($rf | Where-Object { $_.Status -eq 'FAIL' }).Count
  $w1 = @($rf | Where-Object { $_.Status -eq 'WARN' }).Count
  $worst = 'PASS'; if ($w1 -gt 0) { $worst = 'WARN' }; if ($f1 -gt 0) { $worst = 'FAIL' }
  [void]$sb.AppendLine("| $($rec.Id) | $($rec.Screening) | $worst | $f1 | $w1 |")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Failures')
[void]$sb.AppendLine('')
if ($fail.Count -eq 0) { [void]$sb.AppendLine('None.') }
foreach ($x in $fail) { [void]$sb.AppendLine("- **$($x.Record)** - $($x.Check): $($x.Detail)") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Warnings (review by hand)')
[void]$sb.AppendLine('')
if ($warn.Count -eq 0) { [void]$sb.AppendLine('None.') }
foreach ($x in $warn) { [void]$sb.AppendLine("- **$($x.Record)** - $($x.Check): $($x.Detail)") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Not checked by this script')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- Whether each statement in the report is supported by the cited study (the numeric trace only finds numbers absent from the sources).')
[void]$sb.AppendLine('- Extracted evidence and appraisal against the paper itself.')
[void]$sb.AppendLine('- Publisher pages that block automated requests (reported as WARN).')
$outDirPath = Split-Path -Parent $OutFile
if (-not (Test-Path $outDirPath)) { New-Item -ItemType Directory -Path $outDirPath | Out-Null }
[IO.File]::WriteAllText($OutFile, $sb.ToString(), $utf8)

Write-Host ''
Write-Host ("FAIL=" + $fail.Count + " WARN=" + $warn.Count + " PASS=" + $pass.Count)
Write-Host ("Report: " + $OutFile)
if ($fail.Count -gt 0) { exit 1 }
exit 0
