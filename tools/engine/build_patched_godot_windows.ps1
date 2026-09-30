param(
    [string]$WorkRoot = (Join-Path $env:USERPROFILE "hfn-godot-4.8-dev6"),
    [int]$Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 1),
    [switch]$VerifyProject
)

$ErrorActionPreference = "Stop"
$UpstreamCommit = "8898c2b3db32adf6f92c694ffb6dac19af672e5f"
$RepoUrl = "https://github.com/godotengine/godot.git"
$Patcher = Join-Path $PSScriptRoot "apply_directional_shadow_sampler.py"
$GodotDir = Join-Path $WorkRoot "godot"

foreach ($tool in @("git", "python", "scons", "dotnet")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' is not available in PATH."
    }
}

New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

if (-not (Test-Path (Join-Path $GodotDir ".git"))) {
    git clone $RepoUrl $GodotDir
    if ($LASTEXITCODE -ne 0) { throw "Godot clone failed." }
}

Push-Location $GodotDir
try {
    git fetch origin $UpstreamCommit
    if ($LASTEXITCODE -ne 0) { throw "Fetching pinned Godot 4.8-dev6 commit failed." }

    git checkout --detach $UpstreamCommit
    if ($LASTEXITCODE -ne 0) { throw "Checking out pinned Godot commit failed." }

    # Always restore tracked engine sources before applying HFN's deterministic
    # source patch. Untracked SCons/bin outputs are intentionally kept so a
    # retry does not throw away already compiled objects.
    git reset --hard $UpstreamCommit
    if ($LASTEXITCODE -ne 0) { throw "Resetting Godot source tree failed." }

    python $Patcher --godot-dir $GodotDir
    if ($LASTEXITCODE -ne 0) { throw "Applying HFN directional-shadow engine patch failed." }

    git diff --check
    if ($LASTEXITCODE -ne 0) { throw "Patched Godot source failed git diff --check." }

    Write-Host ""
    Write-Host "HFN engine source patch validated. Building with $Jobs jobs..."

    $env:GODOT_VERSION_STATUS = "dev6"

    # Pass -j and its integer as separate native arguments. '-j$Jobs' can be
    # forwarded literally by PowerShell and makes SCons reject the value.
    scons platform=windows target=editor module_mono_enabled=yes -j $Jobs
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

        & $Editor.FullName --headless --path $ProjectRoot --script tests/systems/test_stylized_shadows.gd
        if ($LASTEXITCODE -ne 0) {
            throw "Stylized-shadow sampler contract test failed under patched Godot."
        }

        Write-Host "HFN project import and custom shadow sampler contract passed."
    }
}
finally {
    Pop-Location
}
