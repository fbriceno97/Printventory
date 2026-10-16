# Felix Printventory customizations

This branch is based on upstream Printventory commit:

`9d3d4a783f950693efc85694905619f4cbbff179` (Printventory 2.2.11)

It preserves the custom setup used for an ARM64 / OMV deployment and adds a
Windows-side Bambu Studio bridge for Docker/server mode.

## What is custom here

- `custom/server/server-bridge.bambu.js`
  - Exact upstream `server-bridge.js` from the 2.2.11 base commit.
  - Adds a synthetic **Bambu Studio** client slicer.
  - Converts Printventory model paths into a custom `printventory-bambu:` URL.
  - Does not download or copy the model.

- `custom/windows/install-printventory-bambu-bridge.ps1`
  - One-time installer for each Windows workstation.
  - Compiles a small local helper EXE.
  - Registers the `printventory-bambu:` URL protocol for the current Windows user.
  - Maps `/mnt/models/...` to the configured SMB/NAS model root.
  - Launches Bambu Studio with the existing NAS file.
  - Rejects path traversal and unsupported extensions.
  - Does not use PowerShell or cmd.exe in the permanent browser launch chain.

- `custom/server/compose.override.example.yml`
  - Example bind mount for the patched server bridge.

## Windows install

Open normal PowerShell on each Windows PC and run the installer from this repo.

Example NAS root:

    \\Rpi48\bricenoshd2\3D Printer Files

Optional test model relative path:

    _JESUS\_MINECRAFT_BASED\_JESUS\SEATED CHRIST\Hocker1.3mf

## Server deployment

The patched bridge replaces `/app/server-bridge.js` in the Printventory container
using a read-only bind mount. Recreate only the Printventory service after changing
the mount. A model rescan is not required just to change the browser bridge.

## Path mapping

Server-side model path:

    /mnt/models/<relative model path>

Windows SMB path:

    \\Rpi48\bricenoshd2\3D Printer Files\<relative model path>

The Windows helper performs that conversion locally and launches Bambu Studio with
the existing NAS file. The model is not downloaded or copied.

## Security

Do not commit API keys, passwords, SMB credentials, or Printventory database secrets.
