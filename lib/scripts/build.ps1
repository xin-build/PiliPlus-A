param(
    [string]$Arg = ''
)

try {
    $versionName = $null

    $versionCode = [int](git rev-list --count HEAD).Trim()

    $commitHash = (git rev-parse HEAD).Trim()

    # Detect release version from tag if available (e.g. v2.1.4.1 or release-2.1.4.1)
    $tagVersion = $null
    $targetTag = if ($env:tag) { $env:tag } elseif ($env:GITHUB_REF_NAME) { $env:GITHUB_REF_NAME } else { $null }
    if ($targetTag -and ($targetTag -match 'v?(\d+\.\d+\.\d+(\.\d+)?)')) {
        $tagVersion = $matches[1]
    }

    $updatedContent = foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
        if ($line -match '^\s*version:\s*([^\+\s]+)') {
            $rawPubVersion = $matches[1]
            if ($rawPubVersion -match '^(\d+\.\d+\.\d+)') {
                $semverPubVersion = $matches[1]
            } else {
                $semverPubVersion = $rawPubVersion
            }
            $versionName = if ($tagVersion) { $tagVersion } else { $semverPubVersion }
            if ($Arg -eq 'android') {
                $versionName += '-' + $commitHash.Substring(0, 9)
            }
            # pubspec.yaml MUST remain valid 3-part SemVer (X.Y.Z+build)
            # otherwise Flutter build/pub tools fail with 'Invalid version number'
            "version: $semverPubVersion+$versionCode"
        }
        else {
            $line
        }
    }

    if ($null -eq $versionName) {
        throw 'version not found'
    }

    $pubspecPath = (Resolve-Path 'pubspec.yaml').Path
    [System.IO.File]::WriteAllLines($pubspecPath, [string[]]$updatedContent, [System.Text.UTF8Encoding]::new($false))

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

    $data = @{
        'pili.name' = $versionName
        'pili.code' = $versionCode
        'pili.hash' = $commitHash
        'pili.time' = $buildTime
    }

    $data | ConvertTo-Json -Compress | Out-File 'pili_release.json' -Encoding UTF8

    if ($env:GITHUB_ENV) {
        Add-Content -Path $env:GITHUB_ENV -Value "version=$versionName+$versionCode"
    }
}
catch {
    Write-Error "Prebuild Error: $($_.Exception.Message)"
    exit 1
}