SET USBDRIVE=%USBDrive%

bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /enum | find "osdevice" > GUID.txt
For /F "tokens=2 delims={}" %%i in (GUID.txt) do (set _NEWGUID=%%i)
bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /copy {default} /d "Windows Setup (arm64)" > GUID2.txt
For /F "tokens=2 delims={}" %%i in (GUID2.txt) do (set _NEWGUID2=%%i)
bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /set {%_NEWGUID2%} device ramdisk=[boot]\sources\arm64\boot.wim,{%_NEWGUID%}
bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /set {%_NEWGUID2%} osdevice ramdisk=[boot]\sources\arm64\boot.wim,{%_NEWGUID%}
bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /set {%_NEWGUID2%} systemroot \windows
bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /set {bootmgr} displaybootmenu yes
bcdedit /store %USBDRIVE%\EFI\Microsoft\Boot\BCD /set {bootmgr} timeout 5