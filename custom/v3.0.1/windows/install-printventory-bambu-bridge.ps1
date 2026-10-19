param(
    [string]$NasRoot = "\\Rpi48\bricenoshd2\3D Printer Files",
    [string]$BambuStudio = "",
    [string]$TestRelativePath = "",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$Base = Join-Path $env:LOCALAPPDATA "PrintventoryBambuBridge"
$Source = Join-Path $Base "PrintventoryBambuBridge.cs"
$Exe = Join-Path $Base "PrintventoryBambuBridge.exe"
$ProtocolRoot = "HKCU:\Software\Classes\printventory-bambu"
$CommandKey = "$ProtocolRoot\shell\open\command"

if ($Uninstall) {
    Remove-Item -Path $ProtocolRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $Base -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Printventory Bambu bridge removed."
    exit 0
}

if (-not (Test-Path -LiteralPath $NasRoot)) {
    throw "NAS model root is not accessible: $NasRoot"
}

if (-not $BambuStudio) {
    $ProgramFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $Candidates = @(
        "$env:ProgramFiles\Bambu Studio\bambu-studio.exe",
        $(if ($ProgramFilesX86) { Join-Path $ProgramFilesX86 "Bambu Studio\bambu-studio.exe" }),
        "$env:LOCALAPPDATA\Programs\Bambu Studio\bambu-studio.exe"
    )
    $BambuStudio = $Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

if (-not $BambuStudio -or -not (Test-Path -LiteralPath $BambuStudio -PathType Leaf)) {
    throw "Bambu Studio executable was not found. Pass -BambuStudio with the full path."
}

New-Item -ItemType Directory -Path $Base -Force | Out-Null

$NasForCSharp = $NasRoot.Replace('"','""')
$BambuForCSharp = $BambuStudio.Replace('"','""')

$Code = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace PrintventoryBambuBridge
{
    internal static class Program
    {
        private const string ProtocolPrefix = "printventory-bambu:";
        private const string LinuxPrefix = "/mnt/models/";
        private const string NasRoot = @"__NAS_ROOT__";
        private const string BambuStudio = @"__BAMBU_STUDIO__";

        private static readonly HashSet<string> AllowedExtensions =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                ".3mf", ".stl", ".obj", ".step", ".stp", ".amf", ".ply"
            };

        [STAThread]
        private static void Main(string[] args)
        {
            try
            {
                if (args == null || args.Length != 1)
                {
                    Fail("Exactly one Printventory model URL is required.");
                    return;
                }

                string uri = args[0].Trim().Trim('"');

                if (!uri.StartsWith(ProtocolPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    Fail("Invalid Printventory Bambu protocol URL.");
                    return;
                }

                string encoded = uri.Substring(ProtocolPrefix.Length);
                string linuxPath = Uri.UnescapeDataString(encoded);

                if (!linuxPath.StartsWith(LinuxPrefix, StringComparison.Ordinal))
                {
                    Fail("Blocked path outside /mnt/models.");
                    return;
                }

                string relative = linuxPath.Substring(LinuxPrefix.Length);

                if (relative.Length == 0 ||
                    relative.StartsWith("/") ||
                    relative.StartsWith("\\") ||
                    relative.Contains("\\") ||
                    relative.Contains(":") ||
                    relative.IndexOf('\0') >= 0)
                {
                    Fail("Blocked unsafe model path.");
                    return;
                }

                string relativeWindows = relative.Replace('/', '\\');
                string rootFull = Path.GetFullPath(NasRoot.TrimEnd('\\') + "\\");
                string modelFile = Path.GetFullPath(Path.Combine(rootFull, relativeWindows));

                if (!modelFile.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
                {
                    Fail("Blocked path traversal outside the model library.");
                    return;
                }

                string extension = Path.GetExtension(modelFile) ?? String.Empty;

                if (!AllowedExtensions.Contains(extension))
                {
                    Fail("Blocked unsupported file type: " + extension);
                    return;
                }

                if (!File.Exists(modelFile))
                {
                    Fail("Model file cannot be found:\r\n\r\n" + modelFile);
                    return;
                }

                if (!File.Exists(BambuStudio))
                {
                    Fail("Bambu Studio cannot be found:\r\n\r\n" + BambuStudio);
                    return;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = BambuStudio;
                psi.Arguments = "\"" + modelFile + "\"";
                psi.WorkingDirectory = Path.GetDirectoryName(BambuStudio);
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                Fail(ex.Message);
            }
        }

        private static void Fail(string message)
        {
            MessageBox.Show(message, "Printventory -> Bambu Studio", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }
}
'@

$Code = $Code.Replace("__NAS_ROOT__", $NasForCSharp)
$Code = $Code.Replace("__BAMBU_STUDIO__", $BambuForCSharp)
Set-Content -LiteralPath $Source -Value $Code -Encoding UTF8

$CSC = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $CSC) {
    throw "Windows .NET Framework C# compiler was not found."
}

if (Test-Path -LiteralPath $Exe) {
    Remove-Item -LiteralPath $Exe -Force
}

$CompilerArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/out:$Exe",
    "/reference:System.dll",
    "/reference:System.Core.dll",
    "/reference:System.Windows.Forms.dll",
    $Source
)

& $CSC @CompilerArgs

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Exe)) {
    throw "Bridge compilation failed."
}

Remove-Item -Path $ProtocolRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $ProtocolRoot -Force | Out-Null
Set-Item -Path $ProtocolRoot -Value "URL:Printventory Bambu Studio Bridge"
New-ItemProperty -Path $ProtocolRoot -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
New-Item -Path $CommandKey -Force | Out-Null

$ProtocolCommand = '"' + $Exe + '" "%1"'
Set-Item -Path $CommandKey -Value $ProtocolCommand

$Registered = (Get-Item $CommandKey).GetValue("")

if ($Registered -match "powershell|cmd\.exe") {
    throw "Protocol registration unexpectedly points to a command shell."
}

Write-Host "PASS: Helper installed"
Write-Host "Helper: $Exe"
Write-Host "NAS root: $NasRoot"
Write-Host "Bambu Studio: $BambuStudio"
Write-Host "Protocol: $Registered"

if ($TestRelativePath) {
    $TestFile = Join-Path $NasRoot $TestRelativePath

    if (-not (Test-Path -LiteralPath $TestFile -PathType Leaf)) {
        throw "Test model is not accessible: $TestFile"
    }

    $LinuxPath = "/mnt/models/" + $TestRelativePath.Replace("\","/")
    $TestUri = "printventory-bambu:" + [System.Uri]::EscapeDataString($LinuxPath)

    Write-Host "Testing protocol with: $TestFile"
    Start-Process $TestUri
}
