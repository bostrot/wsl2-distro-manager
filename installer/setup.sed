[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=1
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=%SourceFiles0%\LICENSE
FinishMessage=Installation Complete
TargetName=%EXTRACT_DIR%\wsl2-distro-manager-setup.exe
FriendlyName=WSL2 Distro Manager Installation
AppLaunched=cmd.exe /c setup.bat
PostInstallCmd=
AdminQuietInstCmd=
UserQuietInstCmd=

[Strings]
InstallPrompt=
DisplayLicense=%SourceFiles0%\LICENSE
FinishMessage=Installation Complete
TargetName=%EXTRACT_DIR%\wsl2-distro-manager-setup.exe
FriendlyName=WSL2 Distro Manager Installation
AppLaunched=cmd.exe /c setup.bat
PostInstallCmd=
AdminQuietInstCmd=
UserQuietInstCmd=

[SourceFiles]
SourceFiles0=installer\

[SourceFiles0]
FILE0="setup.bat"
FILE1="vc_redist.x64.exe"
FILE2="desktop_window_plugin.dll"
FILE3="flutter_acrylic_plugin.dll"
FILE4="flutter_localization_plugin.dll"
FILE5="flutter_windows.dll"
FILE6="screen_retriever_windows_plugin.dll"
FILE7="system_theme_plugin.dll"
FILE8="url_launcher_windows_plugin.dll"
FILE9="window_manager_plugin.dll"
FILE10="LICENSE"
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
%FILE5%=
%FILE6%=
%FILE7%=
%FILE8%=
%FILE9%=
%FILE10%=
