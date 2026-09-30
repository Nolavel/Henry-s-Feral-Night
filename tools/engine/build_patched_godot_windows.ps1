param(
    [string]$WorkRoot = (Join-Path $env:USERPROFILE "hfn-godot-4.8-dev6"),
    [int]$Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 1),
    [switch]$VerifyProject
)

$ErrorActionPreference = "Stop"
$UpstreamCommit = "8898c2b3db32adf6f92c694ffb6dac19af672e5f"
$RepoUrl = "https://github.com/godotengine/godot.git"
$Patch = Join-Path $PSScriptRoot "patches\godot-4.8-dev6-directional-shadow-sampler.patch"
$GodotDir = Join-Path $WorkRoot "godot"

foreach ($tool in @("git", "python", "scons", "dotnet")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' is not available in PATH."
    }
}

New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

if (-not (Test-Path (Join-Path $GodotDir ".git"))) {
    git clone $RepoUrl $GodotDir
}

Push-Location $GodotDir
try {
    if ((git status --porcelain).Length -ne 0) {
        throw "Godot source tree is dirty. Use a clean dedicated WorkRoot: $GodotDir"
    }

    git fetch origin $UpstreamCommit
    git checkout --detach $UpstreamCommit

    git apply --check $Patch
    git apply $Patch

    $env:GODOT_VERSION_STATUS = "dev6"

    scons platform=windows target=editor module_mono_enabled=yes -j$Jobs
    if ($LASTEXITCODE -ne 0) { throw "SCons editor build failed." }

    $Editor = Get-ChildItem -Path (Join-Path $GodotDir "bin") -Filter "godot.windows.editor*.mono.exe" |
        Select-Object -First 1
    if ($null -eq $Editor) {
        throw "Patched .NET editor binary was not found under $GodotDir\bin."
    }

    & $Editor.FullName --headless --generate-mono-glue modules/mono/glue
    if ($LASTEXITCODE -ne 0) { throw "Mono glue generation failed." }

    python modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --godot-platform=windows
    if ($LASTEXITCODE -ne 0) { throw ".NET assembly build failed." }

    Write-Host ""
    Write-Host "HFN patched Godot 4.8-dev6 built successfully:"
    Write-Host $Editor.FullName

    if ($VerifyProject) {
        $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        & $Editor.FullName --headless --path $ProjectRoot --editor --quit-after 3
        if ($LASTEXITCODE -ne 0) {
            throw "Project import/compile verification failed under patched Godot."
        }
        Write-Host "HFN project import succeeded with the patched editor."
    }
}
finally {
    Pop-Location
}
