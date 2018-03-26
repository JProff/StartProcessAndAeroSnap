# StartProcessAndAeroSnap
Starts a process using Start-Process cmdlet and set the windows position and size afterwards using SetWindowPos.
Or move windows sending Win+Arrows keys using SendInput.

More in StartProcessAndAeroSnap.ps1 comments.

# Example
```powershell
.\StartProcessAndAeroSnap.ps1

StartProcessAndAeroSnap notepad -SnapPosition L -Width 1500
StartProcessAndAeroSnap notepad -SnapPosition RT -Height 700
StartProcessAndAeroSnap notepad -SnapPosition RB
StartProcessAndAeroSnap notepad -SnapPosition RB
StartProcessAndAeroSnap notepad -Width 873 -Height 739 -PosX 340 -PosY 220
```
