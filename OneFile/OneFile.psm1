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
      • SshKey      — path to an SSH private key, using git-archive over SSH.
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

function Invoke-GitArchiveDownload {
    <#
    .SYNOPSIS
        Download a file via git-archive over SSH.
    #>
    [CmdletBinding()]
    param(
        [string] $Repository,
        [string] $FilePath,
        [string] $Ref,
        [string] $SshKeyPath,
        [string] $OutputPath
    )

    foreach ($cmd in 'git', 'tar') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "'$cmd' is required for SSH key authentication but was not found in PATH."
        }
    }

    if (-not (Test-Path $SshKeyPath -PathType Leaf)) {
        throw "SSH key file not found: $SshKeyPath"
    }

    $sshKeyPath = (Resolve-Path $SshKeyPath).Path

    # Build a cross-platform SSH command that points git at the specified key.
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no -o BatchMode=yes"

    $remote = "git@github.com:${Repository}.git"

    Write-Verbose "git archive --remote=$remote $Ref $FilePath"

    try {
        # git archive emits a TAR stream; pipe it straight to tar to extract the
        # single file to stdout, then write the bytes to OutputPath.
        $tarBytes = & git archive --remote=$remote $Ref $FilePath |
                    & tar --extract --to-stdout $FilePath

        if ($LASTEXITCODE -ne 0) {
            throw "git archive or tar exited with code $LASTEXITCODE."
        }

        # $tarBytes may be a byte array or an array of strings depending on the
        # platform; normalise to bytes and write.
        if ($tarBytes -is [byte[]]) {
            [IO.File]::WriteAllBytes($OutputPath, $tarBytes)
        }
        else {
            $text = $tarBytes -join "`n"
            [IO.File]::WriteAllText($OutputPath, $text)
        }
    }
    finally {
        Remove-Item Env:\GIT_SSH_COMMAND -ErrorAction SilentlyContinue
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

        • SshKey      — supply -SshKeyPath (path to an SSH private key that
                        is authorised for the repository). The file is
                        fetched using 'git archive --remote' over SSH, so
                        git and tar must be available in PATH.

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

    .PARAMETER SshKeyPath
        Path to the SSH private key. Used in the SshKey parameter set.

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
        # SSH key — default ref and output path
        Get-GitHubFile -Repository 'octocat/Hello-World' `
                       -FilePath   'README.md' `
                       -SshKeyPath '~/.ssh/id_rsa'

    .EXAMPLE
        # SSH key — explicit branch and output path
        Get-GitHubFile -Repository  'octocat/Hello-World' `
                       -FilePath    'src/main.py' `
                       -Ref         'develop' `
                       -OutputPath  '.\downloaded_main.py' `
                       -SshKeyPath  '~/.ssh/id_ed25519'

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

        # --- SshKey parameter set ---
        [Parameter(Mandatory, ParameterSetName = 'SshKey',
            HelpMessage = 'Path to the SSH private key.')]
        [string] $SshKeyPath
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

        'SshKey' {
            Write-Host "Downloading '$FilePath' from '$Repository' via SSH key..."
            Invoke-GitArchiveDownload `
                -Repository $Repository `
                -FilePath   $FilePath `
                -Ref        $Ref `
                -SshKeyPath $SshKeyPath `
                -OutputPath $OutputPath
        }
    }

    Write-Host "Saved to: $OutputPath"
    Get-Item $OutputPath
}

Export-ModuleMember -Function Get-GitHubFile
