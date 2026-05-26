# one-file

Scripts to download a single file from a GitHub repository **without cloning the whole repository**.
Authentication is supported via username + password / personal access token (HTTPS) or an SSH private key.

Two implementations are provided:

| Script | Platform | Format |
|--------|----------|--------|
| `download-one-file.sh` | Unix / macOS / Linux | Bash shell script |
| `OneFile/` | Windows / cross-platform | PowerShell module |

---

## Shell script — `download-one-file.sh`

### Requirements

| Auth method | Tools needed |
|-------------|-------------|
| Username / password | `curl`, and one of `python3` / `python` / (`jq` + `base64`) |
| SSH key | `git`, `ssh`, `tar` |

### Usage

```text
download-one-file.sh [OPTIONS]

Authentication (choose one):
  -u USERNAME    GitHub username
  -p PASSWORD    GitHub password or personal access token
  -k KEY_PATH    Path to SSH private key

Required:
  -r OWNER/REPO  Repository (e.g. octocat/Hello-World)
  -f FILE_PATH   Path to the target file inside the repository

Optional:
  -b REF         Branch, tag, or commit SHA (default: HEAD)
  -o OUTPUT      Local destination path (default: basename of FILE_PATH)
  -h             Show help
```

### Examples

```bash
# HTTPS — username and personal access token
./download-one-file.sh -u myuser -p ghp_mytoken \
    -r octocat/Hello-World -f README.md

# HTTPS — explicit branch and output path
./download-one-file.sh -u myuser -p ghp_mytoken \
    -r octocat/Hello-World -f src/main.py -b develop -o ./main.py

# SSH key
./download-one-file.sh -k ~/.ssh/id_rsa \
    -r octocat/Hello-World -f README.md

# SSH key — explicit branch and output path
./download-one-file.sh -k ~/.ssh/id_ed25519 \
    -r octocat/Hello-World -f src/main.py -b develop -o ./main.py
```

---

## PowerShell module — `OneFile`

### Requirements

- PowerShell 7.0 or later
- SSH key mode additionally requires `git` and `tar` in `PATH`

### Installation

```powershell
# Import directly from the cloned/downloaded folder
Import-Module ./OneFile/OneFile.psd1
```

### Usage

```
Get-GitHubFile [-Repository] <string> [-FilePath] <string>
               [-Ref <string>] [-OutputPath <string>]
               -Username <string> -Password <string>
               [<CommonParameters>]

Get-GitHubFile [-Repository] <string> [-FilePath] <string>
               [-Ref <string>] [-OutputPath <string>]
               -SshKeyPath <string>
               [<CommonParameters>]
```

### Examples

```powershell
# HTTPS — username and personal access token
Get-GitHubFile -Repository 'octocat/Hello-World' `
               -FilePath   'README.md' `
               -Username   'myuser' `
               -Password   'ghp_myPersonalAccessToken'

# HTTPS — explicit branch and output path
Get-GitHubFile -Repository  'octocat/Hello-World' `
               -FilePath    'src/main.py' `
               -Ref         'develop' `
               -OutputPath  'C:\Downloads\main.py' `
               -Username    'myuser' `
               -Password    'ghp_myPersonalAccessToken'

# SSH key
Get-GitHubFile -Repository 'octocat/Hello-World' `
               -FilePath   'README.md' `
               -SshKeyPath '~/.ssh/id_rsa'

# SSH key — explicit branch and output path
Get-GitHubFile -Repository  'octocat/Hello-World' `
               -FilePath    'src/main.py' `
               -Ref         'develop' `
               -OutputPath  '.\downloaded_main.py' `
               -SshKeyPath  '~/.ssh/id_ed25519'
```

The command returns a `System.IO.FileInfo` object representing the downloaded file, so it can be piped to further PowerShell commands.

### Full help

```powershell
Get-Help Get-GitHubFile -Full
```