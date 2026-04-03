# Installer

This folder contains the Inno Setup installer.

## What it does
- Installs the app into `C:\Program Files\WSL2 Distro Manager`
- Uses InnoDependencyInstaller to download/install Microsoft Visual C++ 2015-2022 redistributable when required
- Creates a Start Menu shortcut

## Build flow
1. Build the Windows release output.
2. Run `build-installer.ps1` from this folder.

It will:
- Stage the release files into `installer/payload`.
- Download `CodeDependencies.iss` from InnoDependencyInstaller when missing.
- Compile the Inno Setup script `setup.iss`.
- Output `installer/wsl2-distro-manager-setup.exe`.

`stage-payload.ps1` by itself does not create an installer executable.

## Notes
- The installer does not ship Microsoft runtime DLLs.
- VC++ runtime is managed via `Dependency_AddVC2015To2022` in `CodeDependencies.iss` (downloaded by `build-installer.ps1` when missing; not committed to git).
- The setup wizard shows the repository root `LICENSE` file.
- The `payload` folder is only a staging area for the app binaries.
- Generated artifacts are ignored via `installer/.gitignore`.