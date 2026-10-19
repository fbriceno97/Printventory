# Felix Printventory 3.0.1 custom build

This branch tracks the working customized Printventory installation used on the OMV Raspberry Pi 4.

## Base version

- Upstream: `TechJeeper/Printventory`
- Printventory: **3.0.1**
- Exact upstream commit: `fcffc838242fe65943d74319924e81bc67f75864`
- Local ARM64 image name: `local/printventory-arm64:3.0.1-fcffc83`

## What is customized

### Direct NAS -> Bambu Studio

Upstream server/Docker mode uses its local helper flow. This customization preserves the existing no-download workflow for Bambu Studio:

```text
/mnt/models/<relative path>
        |
        v
printventory-bambu:<encoded path>
        |
        v
Windows PrintventoryBambuBridge.exe
        |
        v
\\Rpi48\bricenoshd2\3D Printer Files\<relative path>
        |
        v
Bambu Studio
```

The original model stays on the NAS. Printventory does not download or duplicate it.

### Server override files

- `custom/v3.0.1/server/server-bridge.js`
  - Starts from the exact upstream 3.0.1 `server-bridge.js`.
  - Adds a synthetic Bambu Studio workstation slicer.
  - Restores the **Send to Slicer** button in server mode.
  - The visibility override is required because upstream 3.0.1 CSS intentionally hides the slicer controls in server mode.

- `custom/v3.0.1/server/slicer-protocol.js`
  - Starts from the exact upstream 3.0.1 `slicer-protocol.js`.
  - Intercepts Bambu Studio only.
  - Converts `/mnt/models/...` to the custom `printventory-bambu:` protocol.
  - Keeps non-Bambu slicers on the upstream 3.0.1 launch path.
  - Rejects paths outside `/mnt/models/`, ZIP-internal entries, and unsupported file types.

### Windows helper

- `custom/v3.0.1/windows/install-printventory-bambu-bridge.ps1`
  - One-time install on each Windows workstation.
  - Builds a small local helper EXE.
  - Registers the per-user `printventory-bambu:` protocol.
  - Maps the Printventory container path to the SMB/NAS path.
  - Launches Bambu Studio directly with the existing NAS file.
  - The permanent protocol handler points directly to the EXE, not to PowerShell or cmd.exe.

Current working NAS root:

```text
\\Rpi48\bricenoshd2\3D Printer Files
```

## Docker deployment

The live container bind-mounts the customized JavaScript over the two upstream files:

```text
.../overrides-v3.0.1/server-bridge.js  -> /app/server-bridge.js
.../overrides-v3.0.1/slicer-protocol.js -> /app/slicer-protocol.js
```

The model library is mounted read-only:

```text
.../BRICENOSHD2/3D Printer Files -> /mnt/models
```

See `custom/v3.0.1/server/compose.override.example.yml`.

## ARM64 build note for upstream 3.0.1

The 3.0.1 Dockerfile references `support-webhook.json`, while that file is intentionally absent from Git. Before building the upstream source locally, create an empty placeholder:

```bash
: > support-webhook.json
docker build -t local/printventory-arm64:3.0.1-fcffc83 .
```

Do **not** put a webhook URL into the repository.

## Verified production state

After migration from 2.2.11:

- Printventory 3.0.1 healthy
- 7,012 models preserved
- Direct-NAS Bambu bridge active
- **Send to Slicer** restored and tested successfully
- Existing Windows bridge opens the original SMB/NAS model in Bambu Studio
- No model download/copy required

## Security

Never commit:

- Gemini/OpenAI/API keys
- passwords
- SMB credentials
- database secrets
- private webhook URLs
