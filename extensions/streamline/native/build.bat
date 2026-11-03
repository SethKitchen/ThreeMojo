@echo off
rem Copyright (c) 2026 Seth Kitchen, PE
rem SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
rem
rem Build the native Streamline host on Windows with Visual Studio 2022.
rem
rem   extensions\streamline\native\build.bat
rem
rem It downloads the Streamline SDK 2.14.16 from NVIDIA's GitHub release into
rem .cache\streamline, checks its SHA-256, and unpacks it. Set STREAMLINE_SDK
rem to an unpacked SDK to use that one. The program and NVIDIA's signed
rem DLLs go to .cache\streamline\bin. NVIDIA's license covers the DLLs; the
rem repository does not hold them.
setlocal
set ROOT=%~dp0..\..\..
set CACHE=%ROOT%\.cache\streamline
set ZIP=%CACHE%\streamline-sdk-v2.14.16.zip
set SHA=32041e51db0cab709a271b72a352281b690c2abbd669a827809401a5dd23956b
set URL=https://github.com/NVIDIA-RTX/Streamline/releases/download/v2.14.16/streamline-sdk-v2.14.16.zip
if not exist "%CACHE%" mkdir "%CACHE%"
if "%STREAMLINE_SDK%"=="" (
  set STREAMLINE_SDK=%CACHE%\sdk
  if not exist "%CACHE%\sdk\include\sl.h" (
    if not exist "%ZIP%" (
      echo Downloading the Streamline SDK 2.14.16.
      curl.exe -L --fail -o "%ZIP%" "%URL%" || exit /b 1
    )
    powershell -NoProfile -Command "if ((Get-FileHash -Algorithm SHA256 '%ZIP%').Hash -ne '%SHA%') { Write-Error 'The SDK zip has the wrong SHA-256'; exit 1 }" || exit /b 1
    if not exist "%CACHE%\sdk" mkdir "%CACHE%\sdk"
    "%SystemRoot%\System32\tar.exe" -xf "%ZIP%" -C "%CACHE%\sdk" || exit /b 1
  )
)
call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
if not exist "%CACHE%\bin" mkdir "%CACHE%\bin"
copy /y "%STREAMLINE_SDK%\bin\x64\sl.interposer.dll" "%CACHE%\bin\" >nul || exit /b 1
copy /y "%STREAMLINE_SDK%\bin\x64\sl.common.dll" "%CACHE%\bin\" >nul || exit /b 1
copy /y "%STREAMLINE_SDK%\bin\x64\sl.dlss.dll" "%CACHE%\bin\" >nul || exit /b 1
copy /y "%STREAMLINE_SDK%\bin\x64\sl.dlss_d.dll" "%CACHE%\bin\" >nul || exit /b 1
copy /y "%STREAMLINE_SDK%\bin\x64\nvngx_dlss.dll" "%CACHE%\bin\" >nul || exit /b 1
copy /y "%STREAMLINE_SDK%\bin\x64\nvngx_dlssd.dll" "%CACHE%\bin\" >nul || exit /b 1
cl /nologo /O2 /EHsc /std:c++17 /W3 /I"%STREAMLINE_SDK%\include" "%~dp0host.cpp" ^
  /Fo:"%CACHE%\bin\host.obj" /Fe:"%CACHE%\bin\threemojo_streamline.exe" ^
  /link /LIBPATH:"%STREAMLINE_SDK%\lib\x64" sl.interposer.lib d3d12.lib dxgi.lib || exit /b 1
echo Built %CACHE%\bin\threemojo_streamline.exe
