@echo off
REM Check for Redistributable and install if needed
if not exist "C:\Windows\System32\vcruntime140.dll" (
    echo Installing VC++ Redistributable
    :: Uncomment the correct line below for your architecture
    :: vc_redist.x86.exe /install /quiet /norestart
    vc_redist.x64.exe /install /quiet /norestart
)

mkdir "C:\Program Files\WSL Manager"
copy "WSL Manager.exe" "C:\Program Files\WSL Manager"
