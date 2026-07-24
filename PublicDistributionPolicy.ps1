$script:UpdaterPublicPackageId = "com.nickel-jp.avatar-recovery.updater"
$script:UpdaterPublicRepositoryId = "com.nickel-jp.repos.avatar-recovery-updater"
$script:UpdaterPublicRepositoryName = "AvatarRecovery Update Notifier"
$script:UpdaterPublicBaseUrl = "https://nickel-jp.github.io/avatar-recovery-updater-unity"
$script:UpdaterPublicIndexUrl = "$script:UpdaterPublicBaseUrl/index.json"
$script:UpdaterPublicAssemblyName = "NickelJP.AvatarRecoveryUpdater.Editor"
$script:UpdaterPublicAssemblyPath = "Editor/NickelJP.AvatarRecoveryUpdater.Editor.dll"
$script:UpdaterPublicAssemblyMetaPath =
    "Editor/NickelJP.AvatarRecoveryUpdater.Editor.dll.meta"
$script:UpdaterPublicPackageFiles = @(
    "CHANGELOG.md",
    "CHANGELOG.md.meta",
    "Documentation~/index.md",
    "Editor.meta",
    $script:UpdaterPublicAssemblyPath,
    $script:UpdaterPublicAssemblyMetaPath,
    "Editor/Resources.meta",
    "Editor/Resources/AvatarRecoveryReleaseSigning.cer",
    "Editor/Resources/AvatarRecoveryReleaseSigning.cer.meta",
    "LICENSE",
    "LICENSE.meta",
    "README.md",
    "README.md.meta",
    "package.json",
    "package.json.meta")
$script:UpdaterPublicBlockedPackageExtensions = @(
    ".asmdef", ".bat", ".cmd", ".cs", ".csproj", ".exe", ".key",
    ".mdb", ".p12", ".pdb", ".pfx", ".ps1", ".sln")
$script:UpdaterPublicAllowedAssemblyReferences = @(
    "mscorlib",
    "Newtonsoft.Json",
    "System",
    "System.Core",
    "UnityEditor.CoreModule",
    "UnityEngine.CoreModule",
    "UnityEngine.IMGUIModule",
    "UnityEngine.UnityWebRequestModule")
$script:UpdaterPublicRequiredAssemblyReferences = @(
    "Newtonsoft.Json",
    "UnityEditor.CoreModule",
    "UnityEngine.CoreModule",
    "UnityEngine.UnityWebRequestModule")
$script:UpdaterPublicAssemblyMeta = @"
fileFormatVersion: 2
guid: 1693f5157ec74d9295e146140c5f2281
PluginImporter:
  externalObjects: {}
  serializedVersion: 2
  iconMap: {}
  executionOrder: {}
  defineConstraints: []
  isPreloaded: 0
  isOverridable: 1
  isExplicitlyReferenced: 0
  validateReferences: 1
  platformData:
  - first:
      Any:
    second:
      enabled: 0
      settings: {}
  - first:
      Editor: Editor
    second:
      enabled: 1
      settings:
        DefaultValueInitialized: true
  - first:
      Windows Store Apps: WindowsStoreApps
    second:
      enabled: 0
      settings:
        CPU: AnyCPU
  userData:
  assetBundleName:
  assetBundleVariant:
"@
$script:UpdaterWebsiteFiles = @(
    "index.html",
    "styles.css",
    "update/index.html")
$script:UpdaterProvenanceFileName = "provenance.json"
$script:UpdaterPublicRepositoryStaticFiles = @(
    ".gitattributes",
    ".gitignore",
    ".github/dependabot.yml",
    ".github/workflows/pages.yml",
    "CHANGELOG.md",
    "LICENSE",
    "PublicDistributionPolicy.ps1",
    "README.md",
    "Verify-PublicDistribution.ps1")

function Test-UpdaterStableSemanticVersion {
    param([Parameter(Mandatory = $true)][string]$Version)

    return $Version -match '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

function Compare-UpdaterStableSemanticVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    if (-not (Test-UpdaterStableSemanticVersion -Version $Left) -or
        -not (Test-UpdaterStableSemanticVersion -Version $Right)) {
        throw "Only strict stable semantic versions can be compared."
    }

    $leftParts = $Left.Split(".")
    $rightParts = $Right.Split(".")
    for ($index = 0; $index -lt 3; $index++) {
        $leftPart = $leftParts[$index].TrimStart("0")
        $rightPart = $rightParts[$index].TrimStart("0")
        if ([string]::IsNullOrEmpty($leftPart)) {
            $leftPart = "0"
        }
        if ([string]::IsNullOrEmpty($rightPart)) {
            $rightPart = "0"
        }

        if ($leftPart.Length -lt $rightPart.Length) {
            return -1
        }
        if ($leftPart.Length -gt $rightPart.Length) {
            return 1
        }

        $comparison = [string]::Compare(
            $leftPart,
            $rightPart,
            [StringComparison]::Ordinal)
        if ($comparison -lt 0) {
            return -1
        }
        if ($comparison -gt 0) {
            return 1
        }
    }

    return 0
}

function Get-UpdaterNormalizedRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
}

function Assert-UpdaterNoReparsePoints {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootItem = Get-Item -LiteralPath $Root -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Distribution root must not be a reparse point: $Root"
    }

    $reparsePoints = @(Get-ChildItem -LiteralPath $Root -Recurse -Force |
        Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        })
    if ($reparsePoints.Count -gt 0) {
        throw "Distribution tree contains a reparse point: $($reparsePoints[0].FullName)"
    }
}

function Get-UpdaterRelativeFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$ExcludeGitDirectory
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Distribution directory was not found: $Root"
    }
    Assert-UpdaterNoReparsePoints -Root $Root

    $fullRoot = (Get-UpdaterNormalizedRoot -Path $Root) +
        [System.IO.Path]::DirectorySeparatorChar
    $files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($fullRoot.Length).Replace('\', '/')
            if (-not $ExcludeGitDirectory -or
                -not $relativePath.StartsWith(".git/", [StringComparison]::OrdinalIgnoreCase)) {
                $relativePath
            }
        }
    )

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($relativePath in $files) {
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            $relativePath.StartsWith("/", [StringComparison]::Ordinal) -or
            $relativePath.Contains("..") -or
            -not $seen.Add($relativePath)) {
            throw "Distribution tree contains an invalid or duplicate path: $relativePath"
        }
    }

    return @($files | Sort-Object -CaseSensitive)
}

function Assert-UpdaterExactFileSet {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$ExpectedFiles,
        [Parameter(Mandatory = $true)][string]$TreeName,
        [switch]$ExcludeGitDirectory
    )

    $expected = @($ExpectedFiles | Sort-Object -CaseSensitive -Unique)
    if ($expected.Count -ne $ExpectedFiles.Count) {
        throw "$TreeName expected allowlist contains duplicate paths."
    }

    $actual = @(Get-UpdaterRelativeFiles `
        -Root $Root `
        -ExcludeGitDirectory:$ExcludeGitDirectory)
    $difference = @(Compare-Object `
        -ReferenceObject $expected `
        -DifferenceObject $actual `
        -CaseSensitive)
    if ($difference.Count -gt 0) {
        throw "$TreeName file allowlist mismatch: $($difference | Out-String)"
    }

    $expectedDirectories = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($relativePath in $expected) {
        $parent = [System.IO.Path]::GetDirectoryName(
            $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        while (-not [string]::IsNullOrEmpty($parent)) {
            [void]$expectedDirectories.Add($parent.Replace('\', '/'))
            $parent = [System.IO.Path]::GetDirectoryName($parent)
        }
    }
    $fullRoot = (Get-UpdaterNormalizedRoot -Path $Root) +
        [System.IO.Path]::DirectorySeparatorChar
    $actualDirectories = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($fullRoot.Length).
                    Replace('\', '/')
                if (-not $ExcludeGitDirectory -or
                    ($relativePath -cne ".git" -and
                     -not $relativePath.StartsWith(
                        ".git/",
                        [StringComparison]::OrdinalIgnoreCase))) {
                    $relativePath
                }
            } |
            Sort-Object -CaseSensitive
    )
    $directoryDifference = @(Compare-Object `
        -ReferenceObject @($expectedDirectories | Sort-Object -CaseSensitive) `
        -DifferenceObject $actualDirectories `
        -CaseSensitive)
    if ($directoryDifference.Count -gt 0) {
        throw "$TreeName directory allowlist mismatch: $($directoryDifference | Out-String)"
    }
}

function Assert-UpdaterExactJsonProperties {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$ExpectedProperties,
        [Parameter(Mandatory = $true)][string]$ValueName
    )

    if ($null -eq $Value) {
        throw "$ValueName is missing."
    }
    $actual = @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    $expected = @($ExpectedProperties | Sort-Object -CaseSensitive)
    $difference = @(Compare-Object `
        -ReferenceObject $expected `
        -DifferenceObject $actual `
        -CaseSensitive)
    if ($difference.Count -gt 0) {
        throw "$ValueName property allowlist mismatch."
    }
}

function Assert-UpdaterManifestIdentity {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Version,
        [switch]$IndexEntry
    )

    $expectedProperties = @(
        "name",
        "displayName",
        "version",
        "unity",
        "description",
        "type",
        "license",
        "keywords",
        "author",
        "dependencies",
        "url",
        "repo")
    if ($IndexEntry) {
        $expectedProperties += "zipSHA256"
    }
    Assert-UpdaterExactJsonProperties `
        -Value $Manifest `
        -ExpectedProperties $expectedProperties `
        -ValueName "updater package manifest $Version"

    if (-not (Test-UpdaterStableSemanticVersion -Version $Version) -or
        [string]$Manifest.name -cne $script:UpdaterPublicPackageId -or
        [string]$Manifest.displayName -cne $script:UpdaterPublicRepositoryName -or
        [string]$Manifest.version -cne $Version -or
        [string]$Manifest.unity -cne "2022.3" -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.description) -or
        ([string]$Manifest.description).Length -gt 1024 -or
        [string]$Manifest.description -match '[\x00-\x08\x0B\x0C\x0E-\x1F]' -or
        [string]$Manifest.type -cne "tool" -or
        [string]$Manifest.license -cne "SEE LICENSE IN LICENSE" -or
        [string]$Manifest.url -cne (
            "$script:UpdaterPublicBaseUrl/packages/" +
            "$script:UpdaterPublicPackageId-$Version.zip") -or
        [string]$Manifest.repo -cne $script:UpdaterPublicIndexUrl) {
        throw "Updater package manifest identity is invalid for version: $Version"
    }

    $keywords = @($Manifest.keywords)
    $expectedKeywords = @(
        "vrchat",
        "avatar-recovery",
        "update",
        "notifier",
        "editor")
    if (@(Compare-Object `
            -ReferenceObject $expectedKeywords `
            -DifferenceObject $keywords `
            -CaseSensitive).Count -ne 0) {
        throw "Updater package keywords are invalid for version: $Version"
    }

    Assert-UpdaterExactJsonProperties `
        -Value $Manifest.author `
        -ExpectedProperties @("name", "email", "url") `
        -ValueName "updater package author $Version"
    if ([string]$Manifest.author.name -cne "Nickel-JP" -or
        [string]$Manifest.author.email -cne
            "Nickel-JP@users.noreply.github.com" -or
        [string]$Manifest.author.url -cne
            "https://github.com/Nickel-JP") {
        throw "Updater package author is invalid for version: $Version"
    }

    $dependencies = @($Manifest.dependencies.PSObject.Properties)
    if ($dependencies.Count -ne 1 -or
        [string]$dependencies[0].Name -cne
            "com.unity.nuget.newtonsoft-json" -or
        [string]$dependencies[0].Value -cne "3.2.1") {
        throw "Updater package dependencies are invalid for version: $Version"
    }

    if ($IndexEntry -and
        [string]$Manifest.zipSHA256 -cnotmatch '^[0-9a-f]{64}$') {
        throw "Updater package digest is invalid for version: $Version"
    }
}

function Read-UpdaterZipEntryBytes {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Parameter(Mandatory = $true)][long]$MaximumBytes
    )

    $matches = @($Archive.Entries | Where-Object {
        $_.FullName -ceq $EntryName
    })
    if ($matches.Count -ne 1 -or
        $matches[0].Length -le 0 -or
        $matches[0].Length -gt $MaximumBytes) {
        throw "A required package entry is missing or invalid: $EntryName"
    }

    $stream = $matches[0].Open()
    try {
        $memory = New-Object System.IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return ,$memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function ConvertFrom-UpdaterUtf8JsonBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$ValueName
    )

    try {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        return $encoding.GetString($Bytes) | ConvertFrom-Json
    }
    catch {
        throw "$ValueName is not valid UTF-8 JSON: $($_.Exception.Message)"
    }
}

function Import-UpdaterPublicMetadataApi {
    if ("System.Reflection.Metadata.MetadataReader" -as [type]) {
        return
    }

    try {
        Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction Stop
        return
    }
    catch {
        # Windows PowerShell 5.1ではPowerShell 7またはUnity同梱ライブラリを使用します。
    }

    $powerShellMetadataRoot = Join-Path $env:ProgramFiles "PowerShell\7"
    $powerShellImmutablePath = Join-Path $powerShellMetadataRoot (
        "System.Collections.Immutable.dll")
    $powerShellMetadataPath = Join-Path $powerShellMetadataRoot (
        "System.Reflection.Metadata.dll")
    if ((Test-Path -LiteralPath $powerShellImmutablePath -PathType Leaf) -and
        (Test-Path -LiteralPath $powerShellMetadataPath -PathType Leaf)) {
        try {
            Add-Type -Path $powerShellImmutablePath -ErrorAction Stop
            Add-Type -Path $powerShellMetadataPath -ErrorAction Stop
            if ("System.Reflection.Metadata.MetadataReader" -as [type]) {
                return
            }
        }
        catch {
            # PowerShell 7用Assemblyが互換でない場合はUnity同梱版へ切り替えます。
        }
    }

    $unityRoot = Join-Path $env:ProgramFiles "Unity\Hub\Editor"
    if (-not (Test-Path -LiteralPath $unityRoot -PathType Container)) {
        throw "Managed metadata inspection requires PowerShell 7 or Unity 2022.3."
    }
    $unityEditor = Get-ChildItem -LiteralPath $unityRoot -Directory |
        Sort-Object `
            @{ Expression = { $_.Name -match '^2022\.3\.' }; Descending = $true },
            @{ Expression = {
                if ($_.Name -match '^(\d+)\.(\d+)\.(\d+)') {
                    [version]("{0}.{1}.{2}" -f
                        $Matches[1],
                        $Matches[2],
                        $Matches[3])
                }
                else {
                    [version]"0.0.0"
                }
            }; Descending = $true } |
        Select-Object -First 1
    if ($null -eq $unityEditor) {
        throw "A Unity installation containing the metadata API was not found."
    }

    $metadataDirectory = Join-Path $unityEditor.FullName (
        "Editor\Data\MonoBleedingEdge\lib\mono\4.5")
    $immutablePath = Join-Path $metadataDirectory "System.Collections.Immutable.dll"
    $metadataPath = Join-Path $metadataDirectory "System.Reflection.Metadata.dll"
    if (-not (Test-Path -LiteralPath $immutablePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Unity metadata inspection libraries were not found."
    }
    Add-Type -Path $immutablePath -ErrorAction Stop
    Add-Type -Path $metadataPath -ErrorAction Stop
}

function Assert-UpdaterPublicManagedMetadataPolicy {
    param([Parameter(Mandatory = $true)][byte[]]$AssemblyBytes)

    Import-UpdaterPublicMetadataApi
    $stream = [System.IO.MemoryStream]::new(
        [byte[]]$AssemblyBytes,
        $false)
    try {
        $peReader = New-Object `
            System.Reflection.PortableExecutable.PEReader `
            -ArgumentList $stream `
            -ErrorAction Stop
        try {
            if (-not $peReader.HasMetadata) {
                throw "Updater assembly does not contain managed metadata."
            }
            $reader =
                [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader(
                    $peReader)

            foreach ($handle in $reader.TypeReferences) {
                $typeReference = $reader.GetTypeReference($handle)
                $namespace = $reader.GetString($typeReference.Namespace)
                $name = $reader.GetString($typeReference.Name)
                $typeName = if ([string]::IsNullOrEmpty($namespace)) {
                    $name
                }
                else {
                    "$namespace.$name"
                }
                if ($typeName -ceq "System.Diagnostics.Process" -or
                    $typeName -ceq "System.Diagnostics.ProcessStartInfo") {
                    throw "Forbidden updater type reference: $typeName"
                }
            }

            foreach ($handle in $reader.MemberReferences) {
                $memberReference = $reader.GetMemberReference($handle)
                if ($memberReference.Parent.Kind -ne
                    [System.Reflection.Metadata.HandleKind]::TypeReference) {
                    continue
                }
                $typeHandle =
                    [System.Reflection.Metadata.TypeReferenceHandle]$memberReference.Parent
                $typeReference = $reader.GetTypeReference($typeHandle)
                $namespace = $reader.GetString($typeReference.Namespace)
                $name = $reader.GetString($typeReference.Name)
                $memberName = $reader.GetString($memberReference.Name)
                $typeName = if ([string]::IsNullOrEmpty($namespace)) {
                    $name
                }
                else {
                    "$namespace.$name"
                }
                $isForbidden =
                    ($typeName -ceq "System.Diagnostics.Process" -and
                        $memberName -ceq "Start") -or
                    ($typeName -ceq "UnityEditor.PackageManager.Client") -or
                    ($typeName -ceq "UnityEditor.EditorApplication" -and
                        @("Exit", "OpenProject") -ccontains $memberName)
                if ($isForbidden) {
                    throw "Forbidden updater member reference: ${typeName}::${memberName}"
                }
            }

            foreach ($handle in $reader.MethodDefinitions) {
                $method = $reader.GetMethodDefinition($handle)
                if (($method.Attributes -band
                    [System.Reflection.MethodAttributes]::PinvokeImpl) -eq 0) {
                    continue
                }
                $type = $reader.GetTypeDefinition($method.GetDeclaringType())
                $namespace = $reader.GetString($type.Namespace)
                $name = $reader.GetString($type.Name)
                $methodName = $reader.GetString($method.Name)
                $typeName = if ([string]::IsNullOrEmpty($namespace)) {
                    $name
                }
                else {
                    "$namespace.$name"
                }
                throw "P/Invoke is forbidden in the updater assembly: ${typeName}::${methodName}"
            }
        }
        finally {
            if ($null -ne $peReader) {
                $peReader.Dispose()
            }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-UpdaterManagedAssemblyEvidence {
    param([Parameter(Mandatory = $true)][byte[]]$AssemblyBytes)

    try {
        $assembly = [System.Reflection.Assembly]::Load($AssemblyBytes)
    }
    catch {
        throw "The updater assembly is not a valid managed assembly: $($_.Exception.Message)"
    }
    if ($assembly.GetName().Name -cne $script:UpdaterPublicAssemblyName -or
        -not [string]::IsNullOrEmpty($assembly.GetName().CultureName) -or
        $assembly.GetName().GetPublicKeyToken().Length -ne 0) {
        throw "The updater managed assembly identity is invalid."
    }

    $references = @($assembly.GetReferencedAssemblies().Name |
        Sort-Object -CaseSensitive)
    foreach ($reference in $references) {
        if ($script:UpdaterPublicAllowedAssemblyReferences -cnotcontains
            $reference) {
            throw "The updater managed assembly has an unexpected reference: $reference"
        }
    }
    foreach ($requiredReference in $script:UpdaterPublicRequiredAssemblyReferences) {
        if ($references -cnotcontains $requiredReference) {
            throw "The updater managed assembly is missing a required reference: $requiredReference"
        }
    }

    $peKind = [System.Reflection.PortableExecutableKinds]0
    $machine = [System.Reflection.ImageFileMachine]::I386
    $assembly.ManifestModule.GetPEKind([ref]$peKind, [ref]$machine)
    if (($peKind -band [System.Reflection.PortableExecutableKinds]::ILOnly) -eq 0) {
        throw "The updater assembly must contain managed IL."
    }
    Assert-UpdaterPublicManagedMetadataPolicy -AssemblyBytes $AssemblyBytes

    $fingerprints = @($assembly.GetCustomAttributesData() | Where-Object {
        $_.AttributeType.FullName -eq "System.Reflection.AssemblyMetadataAttribute" -and
        $_.ConstructorArguments.Count -eq 2 -and
        [string]$_.ConstructorArguments[0].Value -ceq
            "AvatarRecoveryUpdater.SourceFingerprint"
    })
    if ($fingerprints.Count -ne 1) {
        throw "The updater assembly source fingerprint is missing or duplicated."
    }
    $sourceFingerprint = [string]$fingerprints[0].ConstructorArguments[1].Value
    if ($sourceFingerprint -cnotmatch '^[0-9a-f]{64}$') {
        throw "The updater assembly source fingerprint is invalid."
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $assemblySha256 = ([BitConverter]::ToString(
            $sha256.ComputeHash($AssemblyBytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }

    return [PSCustomObject]@{
        AssemblySha256 = $assemblySha256
        SourceFingerprint = $sourceFingerprint
    }
}

function Assert-UpdaterPackageArchive {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if (-not (Test-UpdaterStableSemanticVersion -Version $Version)) {
        throw "Package archive version is invalid: $Version"
    }
    $packageFile = Get-Item -LiteralPath $PackagePath
    if ($packageFile.Length -le 0 -or $packageFile.Length -gt 32MB) {
        throw "Package archive size is invalid: $Version"
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entryNames = @(
            foreach ($entry in $archive.Entries) {
                $entryName = $entry.FullName.Replace('\', '/')
                if ([string]::IsNullOrEmpty($entry.Name) -or
                    $entry.FullName -cne $entryName -or
                    $entryName.StartsWith("/", [StringComparison]::Ordinal) -or
                    $entryName.Contains("../") -or
                    $entryName.Contains("/..") -or
                    [System.IO.Path]::IsPathRooted($entryName)) {
                    throw "Package archive contains an invalid entry path: $entryName"
                }
                $entryName
            }
        )
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::OrdinalIgnoreCase)
        foreach ($entryName in $entryNames) {
            if (-not $seen.Add($entryName)) {
                throw "Package archive contains duplicate entry paths: $entryName"
            }
        }
        if (@(Compare-Object `
                -ReferenceObject @($script:UpdaterPublicPackageFiles |
                    Sort-Object -CaseSensitive) `
                -DifferenceObject @($entryNames | Sort-Object -CaseSensitive) `
                -CaseSensitive).Count -ne 0) {
            throw "Package archive file allowlist is invalid for version: $Version"
        }

        foreach ($entry in $archive.Entries) {
            $maximumBytes = if ($entry.FullName -ceq
                $script:UpdaterPublicAssemblyPath) {
                16MB
            }
            else {
                1MB
            }
            if ($entry.Length -le 0 -or $entry.Length -gt $maximumBytes) {
                throw "Package archive entry size is invalid: $($entry.FullName)"
            }
            if ($script:UpdaterPublicBlockedPackageExtensions -ccontains
                [System.IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()) {
                throw "Package archive contains a forbidden file: $($entry.FullName)"
            }
        }

        $manifestBytes = Read-UpdaterZipEntryBytes `
            -Archive $archive `
            -EntryName "package.json" `
            -MaximumBytes 256KB
        $manifest = ConvertFrom-UpdaterUtf8JsonBytes `
            -Bytes $manifestBytes `
            -ValueName "package.json for $Version"
        Assert-UpdaterManifestIdentity `
            -Manifest $manifest `
            -Version $Version

        $assemblyMetaBytes = Read-UpdaterZipEntryBytes `
            -Archive $archive `
            -EntryName $script:UpdaterPublicAssemblyMetaPath `
            -MaximumBytes 64KB
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $assemblyMeta = (($strictUtf8.GetString($assemblyMetaBytes).
                Replace("`r`n", "`n").Replace("`r", "`n").
                TrimEnd([char[]]"`n")).Split("`n") |
            ForEach-Object { $_.TrimEnd() }) -join "`n"
        $expectedAssemblyMeta = (($script:UpdaterPublicAssemblyMeta.
                Replace("`r`n", "`n").Replace("`r", "`n").
                TrimEnd([char[]]"`n")).Split("`n") |
            ForEach-Object { $_.TrimEnd() }) -join "`n"
        if ($assemblyMeta -cne $expectedAssemblyMeta) {
            throw "The updater PluginImporter metadata policy is invalid."
        }

        $assemblyBytes = Read-UpdaterZipEntryBytes `
            -Archive $archive `
            -EntryName $script:UpdaterPublicAssemblyPath `
            -MaximumBytes 16MB
        $evidence = Get-UpdaterManagedAssemblyEvidence -AssemblyBytes $assemblyBytes

        $certificateBytes = Read-UpdaterZipEntryBytes `
            -Archive $archive `
            -EntryName "Editor/Resources/AvatarRecoveryReleaseSigning.cer" `
            -MaximumBytes 64KB
        try {
            $certificate =
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    [byte[]]$certificateBytes)
            try {
                if ($certificate.HasPrivateKey) {
                    throw "The public package certificate must not contain a private key."
                }
            }
            finally {
                $certificate.Dispose()
            }
        }
        catch {
            throw "The public package certificate is invalid: $($_.Exception.Message)"
        }

        return [PSCustomObject]@{
            Manifest = $manifest
            AssemblyEvidence = $evidence
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Read-UpdaterDistributionIndex {
    param([Parameter(Mandatory = $true)][string]$Root)

    $indexPath = Join-Path $Root "index.json"
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw "Distribution index was not found: $indexPath"
    }
    $indexFile = Get-Item -LiteralPath $indexPath
    if ($indexFile.Length -le 0 -or $indexFile.Length -gt 8MB) {
        throw "Distribution index size is invalid."
    }

    try {
        $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "Distribution index is not valid JSON: $($_.Exception.Message)"
    }

    Assert-UpdaterExactJsonProperties `
        -Value $index `
        -ExpectedProperties @("name", "id", "url", "author", "packages") `
        -ValueName "repository index"
    if ([string]$index.name -cne $script:UpdaterPublicRepositoryName -or
        [string]$index.id -cne $script:UpdaterPublicRepositoryId -or
        [string]$index.url -cne $script:UpdaterPublicIndexUrl -or
        [string]$index.author -cne "Nickel-JP") {
        throw "Distribution repository identity is invalid."
    }

    $packageProperties = @($index.packages.PSObject.Properties)
    if ($packageProperties.Count -ne 1 -or
        [string]$packageProperties[0].Name -cne $script:UpdaterPublicPackageId) {
        throw "Distribution index must contain exactly the updater package."
    }
    $packageValue = $packageProperties[0].Value
    Assert-UpdaterExactJsonProperties `
        -Value $packageValue `
        -ExpectedProperties @("versions") `
        -ValueName "repository package"

    $versionProperties = @($packageValue.versions.PSObject.Properties)
    if ($versionProperties.Count -lt 1) {
        throw "Distribution index has no package versions."
    }

    $versions = New-Object System.Collections.Generic.List[object]
    $previousVersion = $null
    foreach ($versionProperty in $versionProperties) {
        $version = [string]$versionProperty.Name
        if (-not (Test-UpdaterStableSemanticVersion -Version $version)) {
            throw "Distribution index contains a non-stable semantic version: $version"
        }
        if ($null -ne $previousVersion -and
            (Compare-UpdaterStableSemanticVersion `
                -Left $previousVersion `
                -Right $version) -ge 0) {
            throw "Distribution index versions must be strictly increasing."
        }
        $previousVersion = $version

        $entry = $versionProperty.Value
        Assert-UpdaterManifestIdentity `
            -Manifest $entry `
            -Version $version `
            -IndexEntry

        $packageFileName = "$script:UpdaterPublicPackageId-$version.zip"
        $recordedHash = [string]$entry.zipSHA256

        [void]$versions.Add([PSCustomObject]@{
            Version = $version
            Entry = $entry
            PackageFileName = $packageFileName
            PackageRelativePath = "packages/$packageFileName"
            ChecksumRelativePath =
                "checksums/$script:UpdaterPublicPackageId-$version.sha256.txt"
            PackageSha256 = $recordedHash
        })
    }

    return [PSCustomObject]@{
        Index = $index
        Versions = @($versions.ToArray())
    }
}

function Get-UpdaterVpmExpectedFiles {
    param([Parameter(Mandatory = $true)]$IndexModel)

    return @(
        "index.json"
        foreach ($version in $IndexModel.Versions) {
            [string]$version.PackageRelativePath
            [string]$version.ChecksumRelativePath
        }
    )
}

function Assert-UpdaterReferencedArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$IndexModel
    )

    foreach ($version in $IndexModel.Versions) {
        $packagePath = Join-Path $Root ([string]$version.PackageRelativePath)
        $checksumPath = Join-Path $Root ([string]$version.ChecksumRelativePath)
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
            throw "A referenced distribution artifact is missing for version: $($version.Version)"
        }

        $packageFile = Get-Item -LiteralPath $packagePath
        $checksumFile = Get-Item -LiteralPath $checksumPath
        if ($packageFile.Length -le 0 -or $packageFile.Length -gt 32MB -or
            $checksumFile.Length -le 0 -or $checksumFile.Length -gt 4KB) {
            throw "A referenced distribution artifact has an invalid size: $($version.Version)"
        }

        $actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -cne [string]$version.PackageSha256) {
            throw "A package hash differs from its index entry: $($version.Version)"
        }
        $checksumText = Get-Content -LiteralPath $checksumPath -Raw -Encoding UTF8
        $normalizedChecksum = $checksumText.Replace("`r`n", "`n").Replace("`r", "`n")
        $expectedChecksum = "$actualHash *$($version.PackageRelativePath)`n"
        if ($normalizedChecksum -cne $expectedChecksum) {
            throw "A checksum differs from its package: $($version.Version)"
        }

        $archiveModel = Assert-UpdaterPackageArchive `
            -PackagePath $packagePath `
            -Version ([string]$version.Version)
        foreach ($propertyName in @(
                "name",
                "displayName",
                "version",
                "unity",
                "description",
                "type",
                "license",
                "url",
                "repo")) {
            if ([string]$archiveModel.Manifest.$propertyName -cne
                [string]$version.Entry.$propertyName) {
                throw "Package archive and index differ for $($version.Version): $propertyName"
            }
        }
        foreach ($propertyName in @("keywords", "author", "dependencies")) {
            $archiveJson = $archiveModel.Manifest.$propertyName |
                ConvertTo-Json -Depth 20 -Compress
            $indexJson = $version.Entry.$propertyName |
                ConvertTo-Json -Depth 20 -Compress
            if ($archiveJson -cne $indexJson) {
                throw "Package archive and index differ for $($version.Version): $propertyName"
            }
        }
    }
}

function Assert-UpdaterVpmTree {
    param([Parameter(Mandatory = $true)][string]$Root)

    $model = Read-UpdaterDistributionIndex -Root $Root
    Assert-UpdaterExactFileSet `
        -Root $Root `
        -ExpectedFiles (Get-UpdaterVpmExpectedFiles -IndexModel $model) `
        -TreeName "VPM distribution"
    Assert-UpdaterReferencedArtifacts -Root $Root -IndexModel $model
    return $model
}

function Assert-UpdaterWebsiteTree {
    param([Parameter(Mandatory = $true)][string]$Root)

    Assert-UpdaterExactFileSet `
        -Root $Root `
        -ExpectedFiles $script:UpdaterWebsiteFiles `
        -TreeName "Website"
    foreach ($relativePath in $script:UpdaterWebsiteFiles) {
        $file = Get-Item -LiteralPath (Join-Path $Root $relativePath)
        if ($file.Length -le 0 -or $file.Length -gt 2MB) {
            throw "Website file size is invalid: $relativePath"
        }
    }
}

function Get-UpdaterZipAssemblyEvidence {
    param([Parameter(Mandatory = $true)][string]$PackagePath)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $assemblyBytes = Read-UpdaterZipEntryBytes `
            -Archive $archive `
            -EntryName $script:UpdaterPublicAssemblyPath `
            -MaximumBytes 16MB
    }
    finally {
        $archive.Dispose()
    }
    return Get-UpdaterManagedAssemblyEvidence -AssemblyBytes $assemblyBytes
}

function New-UpdaterPublicProvenance {
    param(
        [Parameter(Mandatory = $true)][string]$VpmRoot,
        [Parameter(Mandatory = $true)][string]$PackageVersion
    )

    $model = Assert-UpdaterVpmTree -Root $VpmRoot
    $latestVersion = $model.Versions[$model.Versions.Count - 1]
    if ([string]$latestVersion.Version -cne $PackageVersion) {
        throw "The provenance package version must be the latest indexed version."
    }
    $version = @($model.Versions | Where-Object {
        [string]$_.Version -ceq $PackageVersion
    })
    if ($version.Count -ne 1) {
        throw "The provenance package version is absent from the VPM index."
    }
    $evidence = Get-UpdaterZipAssemblyEvidence -PackagePath (
        Join-Path $VpmRoot ([string]$version[0].PackageRelativePath))

    return [ordered]@{
        schemaVersion = 1
        repositoryId = $script:UpdaterPublicRepositoryId
        repositoryUrl = $script:UpdaterPublicIndexUrl
        packageId = $script:UpdaterPublicPackageId
        packageVersion = $PackageVersion
        packageZipSha256 = [string]$version[0].PackageSha256
        editorAssemblySha256 = [string]$evidence.AssemblySha256
        sourceFingerprint = [string]$evidence.SourceFingerprint
    }
}

function Assert-UpdaterPagesProvenance {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$IndexModel
    )

    $path = Join-Path $Root $script:UpdaterProvenanceFileName
    $file = Get-Item -LiteralPath $path
    if ($file.Length -le 0 -or $file.Length -gt 64KB) {
        throw "Public provenance size is invalid."
    }
    $provenance = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-UpdaterExactJsonProperties `
        -Value $provenance `
        -ExpectedProperties @(
            "schemaVersion",
            "repositoryId",
            "repositoryUrl",
            "packageId",
            "packageVersion",
            "packageZipSha256",
            "editorAssemblySha256",
            "sourceFingerprint") `
        -ValueName "public provenance"

    $version = @($IndexModel.Versions | Where-Object {
        [string]$_.Version -ceq [string]$provenance.packageVersion
    })
    $latestVersion = $IndexModel.Versions[$IndexModel.Versions.Count - 1]
    if ([int]$provenance.schemaVersion -ne 1 -or
        [string]$provenance.repositoryId -cne $script:UpdaterPublicRepositoryId -or
        [string]$provenance.repositoryUrl -cne $script:UpdaterPublicIndexUrl -or
        [string]$provenance.packageId -cne $script:UpdaterPublicPackageId -or
        $version.Count -ne 1 -or
        [string]$provenance.packageVersion -cne
            [string]$latestVersion.Version -or
        [string]$provenance.packageZipSha256 -cne [string]$version[0].PackageSha256 -or
        [string]$provenance.editorAssemblySha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$provenance.sourceFingerprint -cnotmatch '^[0-9a-f]{64}$') {
        throw "Public provenance identity is invalid."
    }

    $evidence = Get-UpdaterZipAssemblyEvidence -PackagePath (
        Join-Path $Root ([string]$version[0].PackageRelativePath))
    if ([string]$provenance.editorAssemblySha256 -cne [string]$evidence.AssemblySha256 -or
        [string]$provenance.sourceFingerprint -cne [string]$evidence.SourceFingerprint) {
        throw "Public provenance does not match the packaged updater assembly."
    }
    return $provenance
}

function Get-UpdaterPagesExpectedFiles {
    param([Parameter(Mandatory = $true)]$IndexModel)

    return @(
        ".nojekyll"
        "index.html"
        "styles.css"
        "update/index.html"
        "index.json"
        $script:UpdaterProvenanceFileName
        foreach ($version in $IndexModel.Versions) {
            [string]$version.PackageRelativePath
            [string]$version.ChecksumRelativePath
        }
    )
}

function Assert-UpdaterPagesTree {
    param([Parameter(Mandatory = $true)][string]$Root)

    $model = Read-UpdaterDistributionIndex -Root $Root
    Assert-UpdaterExactFileSet `
        -Root $Root `
        -ExpectedFiles (Get-UpdaterPagesExpectedFiles -IndexModel $model) `
        -TreeName "Pages distribution"
    Assert-UpdaterReferencedArtifacts -Root $Root -IndexModel $model
    if ((Get-Item -LiteralPath (Join-Path $Root ".nojekyll")).Length -ne 0) {
        throw ".nojekyll must be empty."
    }
    [void](Assert-UpdaterPagesProvenance -Root $Root -IndexModel $model)
    return $model
}

function Get-UpdaterPublicRepositoryExpectedFiles {
    param([Parameter(Mandatory = $true)]$PagesIndexModel)

    return @(
        foreach ($staticFile in $script:UpdaterPublicRepositoryStaticFiles) {
            $staticFile
        }
        foreach ($siteFile in Get-UpdaterPagesExpectedFiles -IndexModel $PagesIndexModel) {
            "site/$siteFile"
        }
    )
}

function Assert-UpdaterPublicRepositoryTree {
    param([Parameter(Mandatory = $true)][string]$Root)

    $siteRoot = Join-Path $Root "site"
    $model = Assert-UpdaterPagesTree -Root $siteRoot
    Assert-UpdaterExactFileSet `
        -Root $Root `
        -ExpectedFiles (Get-UpdaterPublicRepositoryExpectedFiles -PagesIndexModel $model) `
        -TreeName "public repository" `
        -ExcludeGitDirectory
    return $model
}

function Get-UpdaterDistributionTreeHash {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$ExcludeGitDirectory
    )

    $fullRoot = (Get-UpdaterNormalizedRoot -Path $Root) +
        [System.IO.Path]::DirectorySeparatorChar
    $paths = @(Get-UpdaterRelativeFiles `
        -Root $Root `
        -ExcludeGitDirectory:$ExcludeGitDirectory)
    $memory = New-Object System.IO.MemoryStream
    try {
        $writer = New-Object System.IO.BinaryWriter(
            $memory,
            (New-Object System.Text.UTF8Encoding($false)),
            $true)
        try {
            foreach ($relativePath in $paths) {
                $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($relativePath)
                $contentBytes = [System.IO.File]::ReadAllBytes(
                    (Join-Path $Root $relativePath))
                $writer.Write([int]$pathBytes.Length)
                $writer.Write($pathBytes)
                $writer.Write([long]$contentBytes.Length)
                $writer.Write($contentBytes)
            }
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
        }
        $memory.Position = 0
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString(
                $sha256.ComputeHash($memory))).Replace("-", "").ToLowerInvariant()
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $memory.Dispose()
    }
}
