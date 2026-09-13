[CmdletBinding()]
param(
    [string]$IndexPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "package_azureboard_index.json"),

    [switch]$VerifyArtifacts,

    [string]$PlatformVersion,

    [string]$ToolHost = "i686-mingw32",

    [string]$DownloadDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "azureiotdevkit-index-validation")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ArtifactMetadata {
    param(
        [Parameter(Mandatory = $true)]
        $Artifact,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    foreach ($propertyName in @("url", "archiveFileName", "checksum", "size")) {
        $property = $Artifact.PSObject.Properties[$propertyName]
        if (-not $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "$Context is missing $propertyName."
        }
    }

    $uri = $null
    if (
        -not [Uri]::TryCreate([string]$Artifact.url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne "https"
    ) {
        throw "$Context must use an absolute HTTPS URL."
    }

    $checksum = [string]$Artifact.checksum
    if ($checksum -notmatch "^(MD5|SHA-256):([0-9a-fA-F]+)$") {
        throw "$Context has an unsupported checksum: $checksum"
    }

    $algorithm = $Matches[1]
    $digest = $Matches[2].ToLowerInvariant()
    $requiredLength = if ($algorithm -eq "MD5") { 32 } else { 64 }
    if ($digest.Length -ne $requiredLength) {
        throw "$Context has an invalid $algorithm digest length."
    }

    [long]$size = 0
    if (-not [long]::TryParse(([string]$Artifact.size).Trim(), [ref]$size) -or $size -le 0) {
        throw "$Context has an invalid size: $($Artifact.size)"
    }

    return [pscustomobject]@{
        Algorithm = $algorithm
        Digest = $digest
        Size = $size
    }
}

function Test-ArtifactBytes {
    param(
        [Parameter(Mandatory = $true)]
        $Artifact,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $metadata = Get-ArtifactMetadata -Artifact $Artifact -Context $Context
    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
    $destination = Join-Path $DownloadDirectory ([string]$Artifact.archiveFileName)

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $existingSize = (Get-Item -LiteralPath $destination).Length
        if ($existingSize -ne $metadata.Size) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Write-Host "Downloading $Context..."
        Invoke-WebRequest -Uri ([string]$Artifact.url) -OutFile $destination
    }

    $actualSize = (Get-Item -LiteralPath $destination).Length
    if ($actualSize -ne $metadata.Size) {
        throw "$Context size mismatch. Expected $($metadata.Size), received $actualSize."
    }

    $hashAlgorithm = $metadata.Algorithm.Replace("-", "")
    $actualDigest = (Get-FileHash -LiteralPath $destination -Algorithm $hashAlgorithm).Hash.ToLowerInvariant()
    if ($actualDigest -ne $metadata.Digest) {
        throw "$Context checksum mismatch. Expected $($metadata.Digest), received $actualDigest."
    }

    Write-Host "Verified $Context ($actualSize bytes, $($metadata.Algorithm):$actualDigest)."
}

$resolvedIndexPath = (Resolve-Path -LiteralPath $IndexPath).Path
$index = Get-Content -Raw -LiteralPath $resolvedIndexPath | ConvertFrom-Json
$packages = @($index.packages)
if ($packages.Count -eq 0) {
    throw "The package index does not contain any packages."
}

$toolDefinitions = @{}
$platformCount = 0
$toolSystemCount = 0

foreach ($package in $packages) {
    $packageName = [string]$package.name
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        throw "A package is missing its name."
    }

    foreach ($tool in @($package.tools)) {
        $toolKey = "$packageName|$($tool.name)|$($tool.version)"
        if ($toolDefinitions.ContainsKey($toolKey)) {
            throw "Duplicate tool definition: $toolKey"
        }
        $toolDefinitions[$toolKey] = $tool

        $seenHosts = @{}
        foreach ($system in @($tool.systems)) {
            $systemContext = "tool $($tool.name) $($tool.version) for $($system.host)"
            Get-ArtifactMetadata -Artifact $system -Context $systemContext | Out-Null
            if ($seenHosts.ContainsKey([string]$system.host)) {
                throw "Duplicate host in ${toolKey}: $($system.host)"
            }
            $seenHosts[[string]$system.host] = $true
            ++$toolSystemCount
        }
        if ($seenHosts.Count -eq 0) {
            throw "Tool $toolKey does not define any host systems."
        }
    }

    $seenPlatforms = @{}
    foreach ($platform in @($package.platforms)) {
        $platformKey = "$($platform.architecture)|$($platform.version)"
        if ($seenPlatforms.ContainsKey($platformKey)) {
            throw "Duplicate platform definition in ${packageName}: $platformKey"
        }
        $seenPlatforms[$platformKey] = $true
        Get-ArtifactMetadata -Artifact $platform -Context "platform $packageName $platformKey" | Out-Null

        foreach ($dependency in @($platform.toolsDependencies)) {
            $dependencyKey = "$($dependency.packager)|$($dependency.name)|$($dependency.version)"
            if (-not $toolDefinitions.ContainsKey($dependencyKey)) {
                throw "Platform $packageName $platformKey references missing tool $dependencyKey."
            }
        }
        ++$platformCount
    }
}

if ($VerifyArtifacts) {
    $az3166Packages = @($packages | Where-Object { $_.name -eq "AZ3166" })
    if ($az3166Packages.Count -ne 1) {
        throw "Expected exactly one AZ3166 package, found $($az3166Packages.Count)."
    }

    $az3166Package = $az3166Packages[0]
    if ($PlatformVersion) {
        $selectedPlatforms = @($az3166Package.platforms | Where-Object { $_.version -eq $PlatformVersion })
        if ($selectedPlatforms.Count -ne 1) {
            throw "Expected one AZ3166 platform version $PlatformVersion, found $($selectedPlatforms.Count)."
        }
        $selectedPlatform = $selectedPlatforms[0]
    } else {
        $selectedPlatform = @($az3166Package.platforms | Sort-Object { [version]$_.version } -Descending)[0]
    }

    Test-ArtifactBytes -Artifact $selectedPlatform -Context "platform AZ3166 $($selectedPlatform.version)"
    foreach ($dependency in @($selectedPlatform.toolsDependencies)) {
        $dependencyKey = "$($dependency.packager)|$($dependency.name)|$($dependency.version)"
        $tool = $toolDefinitions[$dependencyKey]
        $systems = @($tool.systems | Where-Object { $_.host -eq $ToolHost })
        if ($systems.Count -ne 1) {
            throw "Expected one $ToolHost artifact for $dependencyKey, found $($systems.Count)."
        }
        Test-ArtifactBytes -Artifact $systems[0] -Context "tool $dependencyKey for $ToolHost"
    }
}

Write-Host "Validated $platformCount platforms and $toolSystemCount tool-system artifacts in $resolvedIndexPath."