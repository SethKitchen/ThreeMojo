@echo off
rem Build the Streamline probe. Run it from a Windows machine with Visual Studio 2022.
rem   set STREAMLINE_SDK=C:\path\to\streamline-sdk-v2.14.16
rem   build.bat
if "%STREAMLINE_SDK%"=="" (
  echo Set STREAMLINE_SDK to the folder of the unpacked Streamline SDK.
  exit /b 1
)
call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if not exist out mkdir out
copy /y "%STREAMLINE_SDK%\bin\x64\development\*.dll" out\ >nul
cl /nologo /EHsc /std:c++17 /I"%STREAMLINE_SDK%\include" probe.cpp /Fo:out\probe.obj /Fe:out\probe.exe ^
  /link /LIBPATH:"%STREAMLINE_SDK%\lib\x64" sl.interposer.lib d3d12.lib dxgi.lib
