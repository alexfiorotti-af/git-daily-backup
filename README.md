# git-daily-backup

Daily, unattended backup of a whole folder tree to private GitHub repositories, built for Windows (PowerShell 5.1+, no extra runtime).

I built it for my own setup: dozens of client and product folders on one laptop, a few of them real codebases with auto-deploy, and no backup outside the hard drive. Generic sync tools copy files; this keeps **versioned history** of everything, never publishes half-finished work, and refuses to upload secrets.

> Scripts and on-screen messages are in Brazilian Portuguese. This README is in English.

## What it does

| | |
|---|---|
| **Two backup modes** | `direto` (documents): `add` → `commit` → `push` on the current branch. `snapshot` (code): photographs the working tree, including uncommitted work, into a separate `backup/auto` branch, **without touching `main`, the index or the files**. A push to `main` on Vercel/Netlify would deploy; a snapshot never does. |
| **Secret & size guard** | Every file about to be committed is checked: size limit (GitHub rejects > 100 MB), file names that look like credentials (`.env`, `*.pem`, "password"/"senha" files) and content patterns for real keys (Anthropic, OpenAI, GitHub, AWS, Stripe, Meta, Mercado Pago, Asaas, Resend, private keys, database URLs with passwords). Blocked files stay on disk, are excluded from then on, and trigger a desktop alert. |
| **Monorepo with nested repos** | One repository can cover a whole `Projects` folder; any sub-folder that has its own `.git` is detected and excluded automatically, so nothing is duplicated. |
| **Unattended** | Windows Task Scheduler, hidden launcher, runs at the next boot if the PC was off, lock file against double runs. |
| **Readable report** | Each run writes `ultimo-sync.md` (table + changed files per repo) and appends to a history log. My AI assistant reads it every evening to update project diaries. |

## How the snapshot mode works (the interesting part)

Uses Git plumbing on a **temporary index**, so the user's real staging area is never touched:

```
GIT_INDEX_FILE=.git/af-sync-index
git read-tree HEAD            # start from main
git add -A                    # stage everything, honouring .gitignore
(secret/size checks; offending paths reset to HEAD)
tree=$(git write-tree)
git commit-tree $tree -p HEAD -p <previous snapshot>
git update-ref refs/af/backup <new commit>
git push --force origin refs/af/backup:refs/heads/backup/auto
```

Restoring a file: `git restore --source origin/backup/auto -- path/to/file`.

## Setup

```powershell
cd scripts
copy ..\examples\repos.example.json repos.json   # then edit paths and username
powershell -ExecutionPolicy Bypass -File .\00-diagnostico.ps1   # read-only check
powershell -ExecutionPolicy Bypass -File .\01-preparar.ps1      # installs Git + GitHub CLI via winget, logs in
powershell -ExecutionPolicy Bypass -File .\02-criar-repos.ps1   # creates private repos, shows a preview, asks before first push
powershell -ExecutionPolicy Bypass -File .\03-agendar.ps1 -Testar  # schedules the daily run and runs once
```

`sync.ps1 -Simular` shows what would be uploaded and what would be blocked, without writing anything.

## Files

| Script | Role |
|---|---|
| `lib.ps1` | Shared functions: git wrappers, checks, exclusions, both sync modes, report |
| `sync.ps1` | The daily job |
| `00-diagnostico.ps1` … `03-agendar.ps1` | Guided setup |
| `novo-projeto.ps1` | Gives a folder its own repository |

## How it was built

The code was written with AI (Claude). I defined the requirements and the safety rules, reviewed every behaviour, and tested it end to end against local bare repositories: secrets blocked, nested repos excluded, snapshot parents correct, second run idempotent. That is how I work: AI is the implementation layer; architecture, review and the decision of what is safe to ship are mine.

## License

MIT
