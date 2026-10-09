# commit-skill

Interactive PowerShell skill to stage and commit Git changes.

Usage (from repository root):

```powershell
# Run the script
.\commit-skill\commit.ps1
```

Options presented by the script:
- Enter comma-separated numbers to stage specific files
- Enter `a` to stage all changes (`git add -A`)
- Enter `s` to provide paths manually (space-separated)
- Enter `c` to cancel

Then provide a commit message when prompted.

Notes:
- Requires `git` in PATH and must be run inside a git repository.
- Tested on PowerShell (Windows). Works in PowerShell Core as well.
