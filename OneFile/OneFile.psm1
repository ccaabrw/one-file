#Requires -Version 7.0
<#
.SYNOPSIS
    OneFile — download a single file from a GitHub repository.

.DESCRIPTION
    The OneFile module exposes the Get-GitHubFile command, which downloads
    exactly one file from a GitHub repository without cloning the whole repo.

    Two authentication methods are supported:
      • Credential  — GitHub username and password / personal access token,
                      using the GitHub REST API over HTTPS.
      • GhCli       — the GitHub CLI (gh) using its configured credentials,
                      accessed via the GitHub REST API.
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

function Invoke-GitHubApiDownload {
    <#
    .SYNOPSIS
        Download a file via the GitHub REST API (HTTPS).
    #>
    [CmdletBinding()]
    param(
        [string] $Repository,
        [string] $FilePath,
        [string] $Ref,
        [string] $Username,
        [string] $Password,
        [string] $OutputPath
    )

    $apiUrl = "https://api.github.com/repos/${Repository}/contents/${FilePath}?ref=${Ref}"

    $encodedCredential = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("${Username}:${Password}")
    )

    $headers = @{
        'Authorization' = "Basic $encodedCredential"
        'Accept'        = 'application/vnd.github.v3+json'
        'User-Agent'    = 'OneFile-PowerShell-Module'
    }

    Write-Verbose "GET $apiUrl"

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ErrorAction Stop
    }
    catch {
        $statusCode = $_.Exception.Response?.StatusCode?.value__
        throw "GitHub API request failed (HTTP $statusCode): $_"
    }

    if ($response.type -ne 'file') {
        throw "The path '${FilePath}' does not point to a file in the repository."
    }

    # The API returns base64-encoded content with embedded newlines; strip them.
    $cleanBase64 = $response.content -replace '\s', ''
    $bytes = [Convert]::FromBase64String($cleanBase64)
    [IO.File]::WriteAllBytes($OutputPath, $bytes)
}

function Invoke-GhCliDownload {
    <#
    .SYNOPSIS
        Download a file via the GitHub API using the gh CLI.
    #>
    [CmdletBinding()]
    param(
        [string] $Repository,
        [string] $FilePath,
        [string] $Ref,
        [string] $OutputPath
    )

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "'gh' (GitHub CLI) is required but was not found in PATH. Install from https://cli.github.com/ and run 'gh auth login'."
    }

    $apiPath = "repos/${Repository}/contents/${FilePath}?ref=${Ref}"

    Write-Verbose "gh api $apiPath"

    & gh api $apiPath --header 'Accept: application/vnd.github.raw' --output $OutputPath

    if ($LASTEXITCODE -ne 0) {
        throw "gh api exited with code $LASTEXITCODE."
    }
}

# ---------------------------------------------------------------------------
# Public function
# ---------------------------------------------------------------------------

function Get-GitHubFile {
    <#
    .SYNOPSIS
        Download a single file from a GitHub repository.

    .DESCRIPTION
        Downloads exactly one file from a GitHub repository without cloning
        the whole repository.

        Choose one of two authentication parameter sets:

        • Credential  — supply -Username and -Password (or personal access
                        token). The file is fetched via the GitHub REST API
                        over HTTPS.

        • GhCli       — supply -UseGhCli. The file is fetched via the GitHub
                        REST API using the gh CLI and its configured
                        credentials (run 'gh auth login' beforehand).

    .PARAMETER Repository
        The repository in "OWNER/REPO" format, e.g. 'octocat/Hello-World'.

    .PARAMETER FilePath
        Path to the target file inside the repository, e.g. 'src/main.py'.

    .PARAMETER Ref
        Branch name, tag, or commit SHA to download from. Defaults to 'HEAD'.

    .PARAMETER OutputPath
        Local path where the file will be saved.
        Defaults to the basename of FilePath in the current directory.

    .PARAMETER Username
        GitHub username. Used with -Password in the Credential parameter set.

    .PARAMETER Password
        GitHub password or personal access token. Used with -Username.

    .PARAMETER UseGhCli
        Use the GitHub CLI (gh) and its configured credentials.
        Run 'gh auth login' before using this parameter.

    .EXAMPLE
        # HTTPS — username and personal access token
        Get-GitHubFile -Repository 'octocat/Hello-World' `
                       -FilePath   'README.md' `
                       -Username   'myuser' `
                       -Password   'ghp_myPersonalAccessToken'

    .EXAMPLE
        # HTTPS — explicit branch and output path
        Get-GitHubFile -Repository  'octocat/Hello-World' `
                       -FilePath    'src/main.py' `
                       -Ref         'develop' `
                       -OutputPath  'C:\Downloads\main.py' `
                       -Username    'myuser' `
                       -Password    'ghp_myPersonalAccessToken'

    .EXAMPLE
        # gh CLI — default ref and output path
        Get-GitHubFile -Repository 'octocat/Hello-World' `
                       -FilePath   'README.md' `
                       -UseGhCli

    .EXAMPLE
        # gh CLI — explicit branch and output path
        Get-GitHubFile -Repository  'octocat/Hello-World' `
                       -FilePath    'src/main.py' `
                       -Ref         'develop' `
                       -OutputPath  '.\downloaded_main.py' `
                       -UseGhCli

    .OUTPUTS
        System.IO.FileInfo
        Returns a FileInfo object representing the downloaded file.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0,
            HelpMessage = 'Repository in OWNER/REPO format.')]
        [ValidatePattern('^[^/]+/[^/]+$')]
        [string] $Repository,

        [Parameter(Mandatory, Position = 1,
            HelpMessage = 'Path to the target file inside the repository.')]
        [string] $FilePath,

        [Parameter()]
        [string] $Ref = 'HEAD',

        [Parameter()]
        [string] $OutputPath,

        # --- Credential parameter set ---
        [Parameter(Mandatory, ParameterSetName = 'Credential',
            HelpMessage = 'GitHub username.')]
        [string] $Username,

        [Parameter(Mandatory, ParameterSetName = 'Credential',
            HelpMessage = 'GitHub password or personal access token.')]
        [string] $Password,

        # --- GhCli parameter set ---
        [Parameter(Mandatory, ParameterSetName = 'GhCli',
            HelpMessage = 'Use the GitHub CLI (gh) and its configured credentials.')]
        [switch] $UseGhCli
    )

    # Resolve default output path.
    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-Location) (Split-Path $FilePath -Leaf)
    }

    switch ($PSCmdlet.ParameterSetName) {

        'Credential' {
            Write-Host "Downloading '$FilePath' from '$Repository' via HTTPS..."
            Invoke-GitHubApiDownload `
                -Repository $Repository `
                -FilePath   $FilePath `
                -Ref        $Ref `
                -Username   $Username `
                -Password   $Password `
                -OutputPath $OutputPath
        }

        'GhCli' {
            Write-Host "Downloading '$FilePath' from '$Repository' via GitHub API (gh CLI)..."
            Invoke-GhCliDownload `
                -Repository $Repository `
                -FilePath   $FilePath `
                -Ref        $Ref `
                -OutputPath $OutputPath
        }
    }

    Write-Host "Saved to: $OutputPath"
    Get-Item $OutputPath
}

Export-ModuleMember -Function Get-GitHubFile
