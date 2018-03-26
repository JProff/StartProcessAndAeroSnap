<#
    .SYNOPSIS 
        Start a process and set the window to a given position and size or move using Aero Snap
        
    .DESCRIPTION 
        Starts a process using Start-Process cmdlet and set the windows position and size afterwards using SetWindowPos.
		Or move windows sending Win+Arrows keys using SendInput.
        Any excess parameter will be passed to StartProcess.
        Please be aware of programs that store their window position and size. You may not be able to get them back easily
        if you place them outside of your displays range.
 
    .PARAMETER FilePath
        This parameter specifies the executable file that will be passed to Start-Process. This is a mandatory parameter 
        for StartProcessAndAeroSnap because it is also the only mandatory parameter for Start-Process. This way you will 
        be forced to use it.
 
    .PARAMETER SnapPosition
		[Optional] Specifies snap position:
			Empty string or without this parameter - if you just want to move without snap
			F - snap to Full Screen
			L - snap to Left
			LT - snap to Left Top
			LB - snap to Left Bottom
			R - snap to Right
			RT - snap to Right Top
			RB - snap to Right Bottom		
    
    .PARAMETER Width
        [Optional] Specifies the window's width.
 
    .PARAMETER Height
        [Optional] Specifies the window's height.
 
	.PARAMETER PosX
        [Optional] Specifies the window's PosX position.
 
    .PARAMETER PosY
        [Optional] Specifies the window's PosY position.
 
	.PARAMETER InitialPosX
        [Optional] Helpful if you need snap window to another monitor. Uses with SnapPosition parameter
 
    .PARAMETER InitialPosY
        [Optional] Uses with SnapPosition parameter
 
    .PARAMETER InitialWidth
        [Optional] Uses with SnapPosition parameter
 
    .PARAMETER InitialHeight
        [Optional] Uses with SnapPosition parameter
 
    .PARAMETER StartProcessParameters
        [Optional] Any excess parameters will be passed to Start-Process
 
    .BASED ON 
        Name: Start-ProcessAndSetWindow 
        Author: Thorsten Windrath, https://www.windrath.com
        Version History 
            1.0//Thorsten Windrath - 05/24/2016
                - Initial build 
	.NOTES
        Name: StartProcessAndAeroSnap 
        Author: Eugene Ozerov aka JProff
        Version History 
            1.0//JProff - 26.03.2018
                - Initial build 
	
	.EXAMPLE
		.\StartProcessAndAeroSnap.ps1

		StartProcessAndAeroSnap notepad -SnapPosition L -Width 1500
		StartProcessAndAeroSnap notepad -SnapPosition RT -Height 700
		StartProcessAndAeroSnap notepad -SnapPosition RB
		StartProcessAndAeroSnap notepad -SnapPosition RB
		StartProcessAndAeroSnap notepad -Width 873 -Height 739 -PosX 340 -PosY 220
#>
function global:StartProcessAndAeroSnap() 
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $FilePath,
 
        [Parameter(Mandatory = $false)]
        [string] $SnapPosition = "",
 
        [Parameter(Mandatory = $false)]
        [int] $Width = -1,
         
        [Parameter(Mandatory = $false)]
        [int] $Height = -1,
 
        [Parameter(Mandatory = $false)]
        [int] $PosX = -1,
 
        [Parameter(Mandatory = $false)]
        [int] $PosY = -1,
 
        [Parameter(Mandatory = $false)]
        [int] $InitialWidth = 300,
         
        [Parameter(Mandatory = $false)]
        [int] $InitialHeight = 300,
 
        [Parameter(Mandatory = $false)]
        [int] $InitialPosX = 0,
 
        [Parameter(Mandatory = $false)]
        [int] $InitialPosY = 0,
 
        [Parameter(Mandatory = $false, ValueFromRemainingArguments=$true)]
        $StartProcessParameters
    )
        
    # Invoke process
    $process = "Start-Process -FilePath $FilePath -PassThru $StartProcessParameters" | Invoke-Expression
 
    # We need to get the process' MainWindowHandle. That's not the processes handle or Id!
    if($process -is [System.Array]) { $procId = $process[0].Id } else { $procId = $process.Id }
 
    # ... fallback in case something goes south (wait up to 5 seconds for the process to launch)
    $i = 50  
 
    # ... Start looking for the main window handle. May take a bit of time for the window to show up
    $mainWindowHandle = [System.IntPtr]::Zero
    while($mainWindowHandle -eq [System.IntPtr]::Zero)
    {
       [System.Threading.Thread]::Sleep(100)
       $tmp = Get-Process -Id $procId -ErrorAction SilentlyContinue
 
       if($tmp -ne $null) 
       {
         $mainWindowHandle = $tmp.MainWindowHandle
       }
 
       $i = $i - 1
       if($i -le 0)
       {
         break
       }
    }
    
    # Once we grabbed the MainWindowHandle, we need to use the Win32-API function SetWindowPosition and SendInput (using inline C#)
    if($mainWindowHandle -ne [System.IntPtr]::Zero)
    {
        $CSharpSource = @" 
using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace JProff.Tools.InlinePS
{
    public static class MyMoveWindowWithAeroSnap
    {
        private const ushort DOWN = 0x28;
        private const ushort ESCAPE = 0x1B;
        private const ushort LEFT = 0x25;
        private const ushort LWIN = 0x5B;
        private const ushort RIGHT = 0x27;
        private const int SWP_NOSIZE = 0x01, SWP_NOMOVE = 0x02, SWP_SHOWWINDOW = 0x40, SWP_HIDEWINDOW = 0x80;
        private const ushort UP = 0x26;

        /// <summary>
        ///     Delay between SendInput commands
        /// </summary>
        private static readonly TimeSpan Delay = TimeSpan.FromMilliseconds(100);

        /// <summary>
        ///     Move window or snap with Aero Snap
        /// </summary>
        /// <param name="hWnd">Window handle</param>
        /// <param name="snapPosition">
        ///     Empty string - if you just want to move without snap
        ///     F - snap to Full Screen
        ///     L - snap to Left
        ///     LT - snap to Left Top
        ///     LB - snap to Left Bottom
        ///     R - snap to Right
        ///     RT - snap to Right Top
        ///     RB - snap to Right Bottom
        /// </param>
        /// <param name="width">If null uses default width</param>
        /// <param name="height">If null uses default height</param>
        /// <param name="posX">Uses only if <paramref name="snapPosition" /> - empty string</param>
        /// <param name="posY">Uses only if <paramref name="snapPosition" /> - empty string</param>
        /// <param name="initialX">Helpful if you need snap window to another monitor. Uses with <paramref name="snapPosition" /></param>
        /// <param name="initialY">Uses with <paramref name="snapPosition" /></param>
        /// <param name="initialWidth">Uses with <paramref name="snapPosition" /></param>
        /// <param name="initialHeight">Uses with <paramref name="snapPosition" /></param>
        public static void MoveWindow(IntPtr hWnd, string snapPosition, int width = -1, int height = -1,
            int posX = -1, int posY = -1, int initialX = 0, int initialY = 0, int initialWidth = 300,
            int initialHeight = 300)
        {
            if (string.IsNullOrWhiteSpace(snapPosition))
            {
                SetPosition(hWnd, posX, posY, width, height);
                return;
            }

            var sp = snapPosition.Trim().ToUpper();

            SetPosition(hWnd, initialX, initialY, initialWidth, initialHeight);

            SetForegroundWindow(hWnd);

            var firstParam = sp[0];
            if (firstParam == 'L')
                Snap(LEFT);
            else if (firstParam == 'R')
                Snap(RIGHT);
            else if (firstParam == 'F')
                Snap(UP);

            if (snapPosition.Length == 2)
            {
                var secondParam = sp[1];
                if (secondParam == 'T')
                    Snap(UP);
                else if (secondParam == 'B')
                    Snap(DOWN);
            }

            SetSize(hWnd, width, height);
        }

        private static INPUT GetDown(ushort keyCode)
        {
            return new INPUT
            {
                Type = 1,
                Data =
                {
                    Keyboard =
                        new KEYBDINPUT
                        {
                            KeyCode = keyCode,
                            Scan = 0,
                            Flags = 0,
                            Time = 0,
                            ExtraInfo = IntPtr.Zero
                        }
                }
            };
        }

        private static INPUT[] GetEscapeInputs()
        {
            return new[]
            {
                GetDown(ESCAPE),
                GetUp(ESCAPE)
            };
        }

        private static INPUT[] GetSnapInputs(ushort arrow)
        {
            return new[]
            {
                GetDown(LWIN),
                GetDown(arrow),
                GetUp(arrow),
                GetUp(LWIN)
            };
        }

        private static INPUT GetUp(ushort keyCode)
        {
            return new INPUT
            {
                Type = 1,
                Data =
                {
                    Keyboard =
                        new KEYBDINPUT
                        {
                            KeyCode = keyCode,
                            Scan = 0,
                            Flags = 0x002,
                            Time = 0,
                            ExtraInfo = IntPtr.Zero
                        }
                }
            };
        }

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hwnd, ref Rect rectangle);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint numberOfInputs, INPUT[] inputs, int sizeOfInputStructure);

        private static void SendInputs(INPUT[] inputs)
        {
            SendInput((uint) inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        }

        [DllImport("User32.dll")]
        private static extern int SetForegroundWindow(IntPtr hWnd);

        static void SetPosition(IntPtr handle, int x, int y, int width, int height)
        {
            x = x < 0 ? 0 : x;
            y = y < 0 ? 0 : y;
            SetWindowPos(handle, 0, x, y, 0, 0, SWP_NOSIZE | SWP_HIDEWINDOW);

            if (width > 0 && height > 0)
                SetWindowPos(handle, 0, 0, 0, width, height, SWP_NOMOVE);

            SetWindowPos(handle, 0, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW);
        }

        private static void SetSize(IntPtr handle, int width, int height)
        {
            if (width < 0 && height < 0) return;

            if (width < 0 || height < 0)
            {
                var rect = new Rect();
                GetWindowRect(handle, ref rect);
                height = height < 0 ? rect.Bottom - rect.Top : height;
                width = width < 0 ? rect.Right - rect.Left : width;
            }

            SetWindowPos(handle, 0, 0, 0, width, height, SWP_NOMOVE);
            SetWindowPos(handle, 0, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW);
        }

        [DllImport("user32.dll", EntryPoint = "SetWindowPos")]
        private static extern IntPtr SetWindowPos(IntPtr hWnd, int hWndInsertAfter, int X, int Y, int cx, int cy,
            int uFlags);

        private static void Snap(ushort arrow)
        {
            Thread.Sleep(Delay);
            SendInputs(GetSnapInputs(arrow));
            Thread.Sleep(Delay);
            SendInputs(GetEscapeInputs());
            Thread.Sleep(Delay);
        }

        private struct Rect
        {
            public int Left { get; set; }
            public int Top { get; set; }
            public int Right { get; set; }
            public int Bottom { get; set; }
        }

#pragma warning disable 649
        private struct INPUT
        {
            public uint Type;
            public MOUSEKEYBDHARDWAREINPUT Data;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct MOUSEKEYBDHARDWAREINPUT
        {
            [FieldOffset(0)]
            public MOUSEINPUT Mouse;
            [FieldOffset(0)]
            public KEYBDINPUT Keyboard;
            [FieldOffset(0)]
            public HARDWAREINPUT Hardware;
        }

        private struct KEYBDINPUT
        {
            public ushort KeyCode;
            public ushort Scan;
            public uint Flags;
            public uint Time;
            public IntPtr ExtraInfo;
        }

        private struct MOUSEINPUT
        {
            public int X;
            public int Y;
            public uint MouseData;
            public uint Flags;
            public uint Time;
            public IntPtr ExtraInfo;
        }
        private struct HARDWAREINPUT
        {
            public uint Msg;
            public ushort ParamL;
            public ushort ParamH;
        }
#pragma warning restore 649
    }
}
"@ 
 
        Add-Type -TypeDefinition $CSharpSource -Language CSharp -ErrorAction SilentlyContinue
        [JProff.Tools.InlinePS.MyMoveWindowWithAeroSnap]::MoveWindow($mainWindowHandle, $SnapPosition, $Width, $Height, $PosX, $PosY, $InitialPosX, $InitialPosY, $InitialWidth, $InitialHeight);
    }
    else
    {
      throw "Couldn't find the MainWindowHandle, aborting (your process should be still alive)"
    }
}
