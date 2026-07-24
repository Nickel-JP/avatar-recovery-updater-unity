param(
    [string]$BeforeSha,
    [switch]$AllowInitialPublication
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "PublicDistributionPolicy.ps1")

$expectedRepository = "Nickel-JP/avatar-recovery-updater-unity"
$expectedActor = "Nickel-JP"
$expectedRef = "refs/heads/main"
$publishedIndexUrl =
    "https://nickel-jp.github.io/avatar-recovery-updater-unity/index.json"

function Invoke-PublicGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = @(& git -C $PSScriptRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command failed (git $($Arguments -join ' ')): $($output -join "`n")"
    }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = @($output)
        Text = ($output -join "`n").Trim()
    }
}

function ConvertFrom-PublicIndexJson {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$ValueName
    )

    try {
        $index = $Json | ConvertFrom-Json
    }
    catch {
        throw "$ValueName is not valid JSON: $($_.Exception.Message)"
    }
    Assert-UpdaterExactJsonProperties `
        -Value $index `
        -ExpectedProperties @("name", "id", "url", "author", "packages") `
        -ValueName $ValueName
    if ([string]$index.name -cne $script:UpdaterPublicRepositoryName -or
        [string]$index.id -cne $script:UpdaterPublicRepositoryId -or
        [string]$index.url -cne $script:UpdaterPublicIndexUrl -or
        [string]$index.author -cne "Nickel-JP") {
        throw "$ValueName repository identity is invalid."
    }

    $packages = @($index.packages.PSObject.Properties)
    if ($packages.Count -ne 1 -or
        [string]$packages[0].Name -cne $script:UpdaterPublicPackageId) {
        throw "$ValueName must contain exactly the updater package."
    }
    Assert-UpdaterExactJsonProperties `
        -Value $packages[0].Value `
        -ExpectedProperties @("versions") `
        -ValueName "$ValueName package"

    $versions = [ordered]@{}
    $previousVersion = $null
    foreach ($versionProperty in @(
            $packages[0].Value.versions.PSObject.Properties)) {
        $version = [string]$versionProperty.Name
        Assert-UpdaterManifestIdentity `
            -Manifest $versionProperty.Value `
            -Version $version `
            -IndexEntry
        if ($null -ne $previousVersion -and
            (Compare-UpdaterStableSemanticVersion `
                -Left $previousVersion `
                -Right $version) -ge 0) {
            throw "$ValueName versions must be strictly increasing."
        }
        $previousVersion = $version
        $versions[$version] = $versionProperty.Value
    }
    if ($versions.Count -lt 1) {
        throw "$ValueName has no updater versions."
    }

    return [PSCustomObject]@{
        Index = $index
        Versions = $versions
    }
}

function Assert-PublicVersionEntriesUnchanged {
    param(
        [Parameter(Mandatory = $true)]$ReferenceVersions,
        [Parameter(Mandatory = $true)]$CandidateVersions,
        [Parameter(Mandatory = $true)][string]$ReferenceName
    )

    foreach ($version in $ReferenceVersions.Keys) {
        if (-not $CandidateVersions.Contains($version)) {
            throw "$ReferenceName version is missing from the candidate: $version"
        }
        $referenceJson = $ReferenceVersions[$version] |
            ConvertTo-Json -Depth 80 -Compress
        $candidateJson = $CandidateVersions[$version] |
            ConvertTo-Json -Depth 80 -Compress
        if ($referenceJson -cne $candidateJson) {
            throw "$ReferenceName version was modified: $version"
        }
    }
}

function Get-PublishedIndexResponse {
    param([Parameter(Mandatory = $true)][string]$TemporaryRoot)

    $destination = Join-Path $TemporaryRoot "published-index.json"
    try {
        Invoke-WebRequest `
            -Uri $publishedIndexUrl `
            -OutFile $destination `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -MaximumRedirection 0 `
            -TimeoutSec 20 `
            -UseBasicParsing
        $file = Get-Item -LiteralPath $destination
        if ($file.Length -le 0 -or $file.Length -gt 8MB) {
            throw "Published repository index size is invalid."
        }
        return [PSCustomObject]@{
            StatusCode = 200
            Path = $destination
        }
    }
    catch {
        $statusCode = $null
        if ($null -ne $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 404) {
            return [PSCustomObject]@{
                StatusCode = 404
                Path = $null
            }
        }
        throw
    }
}

function Assert-RemotePackageHashes {
    param(
        [Parameter(Mandatory = $true)]$PublishedVersions,
        [Parameter(Mandatory = $true)][string]$TemporaryRoot
    )

    foreach ($version in $PublishedVersions.Keys) {
        $entry = $PublishedVersions[$version]
        $destination = Join-Path $TemporaryRoot ("published-$version.zip")
        Invoke-WebRequest `
            -Uri ([string]$entry.url) `
            -OutFile $destination `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -MaximumRedirection 0 `
            -TimeoutSec 30 `
            -UseBasicParsing
        $file = Get-Item -LiteralPath $destination
        if ($file.Length -le 0 -or $file.Length -gt 32MB) {
            throw "Published package size is invalid: $version"
        }
        $actualHash = (
            Get-FileHash -LiteralPath $destination -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if ($actualHash -cne [string]$entry.zipSHA256) {
            throw "Published package hash is invalid: $version"
        }
    }
}

$isPullRequest = $env:GITHUB_EVENT_NAME -ceq "pull_request"
if ($env:GITHUB_REPOSITORY -cne $expectedRepository -or
    ($isPullRequest -and $env:GITHUB_BASE_REF -cne "main") -or
    (-not $isPullRequest -and $env:GITHUB_REF -cne $expectedRef)) {
    throw "Public distribution verification may run only on the fixed main repository."
}

$treeHashBefore = Get-UpdaterDistributionTreeHash `
    -Root $PSScriptRoot `
    -ExcludeGitDirectory
$currentSiteModel = Assert-UpdaterPublicRepositoryTree -Root $PSScriptRoot
$currentIndexJson = Get-Content `
    -LiteralPath (Join-Path $PSScriptRoot "site\index.json") `
    -Raw `
    -Encoding UTF8
$current = ConvertFrom-PublicIndexJson `
    -Json $currentIndexJson `
    -ValueName "candidate index"

if (-not [string]::IsNullOrEmpty($BeforeSha)) {
    if ($BeforeSha -cnotmatch '^[0-9a-f]{40}$') {
        throw "The workflow before SHA is invalid."
    }
    if ($BeforeSha -cne ("0" * 40)) {
        $ancestor = Invoke-PublicGit `
            -Arguments @("merge-base", "--is-ancestor", $BeforeSha, "HEAD") `
            -AllowFailure
        if ($ancestor.ExitCode -ne 0) {
            throw "Non-fast-forward public history is forbidden."
        }
    }
}

$headParent = Invoke-PublicGit `
    -Arguments @("rev-parse", "--verify", "HEAD^") `
    -AllowFailure
$historyCommits = @()
if ($headParent.ExitCode -eq 0) {
    $historyResult = Invoke-PublicGit `
        -Arguments @("rev-list", $headParent.Text, "--", "site/index.json")
    $historyCommits = @($historyResult.Output | Where-Object {
        [string]$_ -match '^[0-9a-f]{40}$'
    })
}

$historicalVersions = [ordered]@{}
foreach ($commit in $historyCommits) {
    $exists = Invoke-PublicGit `
        -Arguments @("cat-file", "-e", "${commit}:site/index.json") `
        -AllowFailure
    if ($exists.ExitCode -ne 0) {
        continue
    }
    $historicalJson = (Invoke-PublicGit `
        -Arguments @("show", "${commit}:site/index.json")).Text
    $historical = ConvertFrom-PublicIndexJson `
        -Json $historicalJson `
        -ValueName "historical index $commit"
    foreach ($version in $historical.Versions.Keys) {
        if ($historicalVersions.Contains($version)) {
            $oldJson = $historicalVersions[$version] |
                ConvertTo-Json -Depth 80 -Compress
            $seenJson = $historical.Versions[$version] |
                ConvertTo-Json -Depth 80 -Compress
            if ($oldJson -cne $seenJson) {
                throw "Git history contains a modified published version: $version"
            }
        }
        else {
            $historicalVersions[$version] = $historical.Versions[$version]
        }
    }
}
Assert-PublicVersionEntriesUnchanged `
    -ReferenceVersions $historicalVersions `
    -CandidateVersions $current.Versions `
    -ReferenceName "historical"

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "avatar-recovery-updater-public-verify-" + [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    $publishedResponse = Get-PublishedIndexResponse -TemporaryRoot $temporaryRoot

    if ($historyCommits.Count -eq 0) {
        if (-not $AllowInitialPublication -or
            $env:GITHUB_EVENT_NAME -cne "workflow_dispatch" -or
            $env:GITHUB_ACTOR -cne $expectedActor -or
            $publishedResponse.StatusCode -ne 404 -or
            $current.Versions.Count -ne 1) {
            throw (
                "The first publication requires the one-time owner dispatch, " +
                "an empty publication history, exactly one version, and HTTP 404.")
        }
    }
    else {
        if ($AllowInitialPublication) {
            throw "The one-time initial-publication gate cannot be reused."
        }
        if ($publishedResponse.StatusCode -ne 200) {
            throw "An existing publication must have a reachable public index."
        }
        $publishedJson = Get-Content `
            -LiteralPath $publishedResponse.Path `
            -Raw `
            -Encoding UTF8
        $published = ConvertFrom-PublicIndexJson `
            -Json $publishedJson `
            -ValueName "published index"
        Assert-PublicVersionEntriesUnchanged `
            -ReferenceVersions $published.Versions `
            -CandidateVersions $current.Versions `
            -ReferenceName "published"
        Assert-RemotePackageHashes `
            -PublishedVersions $published.Versions `
            -TemporaryRoot $temporaryRoot

        $knownVersions = New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal)
        foreach ($version in $historicalVersions.Keys) {
            [void]$knownVersions.Add($version)
        }
        foreach ($version in $published.Versions.Keys) {
            [void]$knownVersions.Add($version)
        }
        $newVersions = @($current.Versions.Keys | Where-Object {
            -not $knownVersions.Contains($_)
        })
        if ($newVersions.Count -gt 1) {
            throw "A public release may add at most one new version."
        }
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

if ((Get-UpdaterDistributionTreeHash `
        -Root $PSScriptRoot `
        -ExcludeGitDirectory) -cne $treeHashBefore) {
    throw "Public verification modified the checked distribution tree."
}

Write-Host "Public distribution verification passed."
