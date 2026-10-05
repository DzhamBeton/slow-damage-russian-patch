param([Parameter(Mandatory=$true)][ValidateSet('Install','Uninstall')][string]$Action,
      [Parameter(Mandatory=$true)][string]$GamePath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$GamePath = [IO.Path]::GetFullPath($GamePath)
if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'slow_damage_en.exe'))) { throw 'В выбранной папке нет slow_damage_en.exe.' }
if (Get-Process -Name slow_damage_en -ErrorAction SilentlyContinue) { throw 'Закройте игру перед установкой или удалением перевода.' }
$packageRoot = $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$backupRoot = Join-Path $GamePath '.slowdamage-rus-backup'
$statePath = Join-Path $backupRoot 'installed.json'
function Hash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Target([string]$relative) {
    $resolved = [IO.Path]::GetFullPath((Join-Path $GamePath $relative))
    if (-not $resolved.StartsWith($GamePath.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Неверный путь в манифесте.' }
    return $resolved
}
function Apply-Delta([string]$original,[string]$delta,[string]$destination) {
    Copy-Item -LiteralPath $original -Destination $destination
    $reader = New-Object IO.BinaryReader ([IO.File]::OpenRead($delta))
    try {
        if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'DMP1') { throw 'Повреждён файл изменений.' }
        $sourceSize=$reader.ReadInt64();$targetSize=$reader.ReadInt64()
        $sourceHash=([BitConverter]::ToString($reader.ReadBytes(32))).Replace('-','').ToLowerInvariant()
        $targetHash=([BitConverter]::ToString($reader.ReadBytes(32))).Replace('-','').ToLowerInvariant()
        $count=$reader.ReadInt32()
        if ((Get-Item -LiteralPath $original).Length -ne $sourceSize -or (Hash $original) -ne $sourceHash) { throw 'Исходный архив отличается от поддерживаемого.' }
        if ($targetSize -lt 0 -or $count -lt 0 -or $count -gt 100000) { throw 'Некорректный заголовок изменений.' }
        $stream=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Write)
        try {
            $stream.SetLength($targetSize)
            for ($index=0;$index -lt $count;$index++) {
                $offset=$reader.ReadInt64();$size=$reader.ReadInt32()
                if ($offset -lt 0 -or $size -lt 0 -or $size -gt 1048576 -or $offset+$size -gt $targetSize) { throw 'Некорректный блок изменений.' }
                $bytes=$reader.ReadBytes($size)
                if ($bytes.Length -ne $size) { throw 'Файл изменений обрезан.' }
                $stream.Position=$offset;$stream.Write($bytes,0,$bytes.Length)
            }
            if ($reader.BaseStream.Position -ne $reader.BaseStream.Length) { throw 'Лишние данные в файле изменений.' }
        } finally { $stream.Dispose() }
        if ((Hash $destination) -ne $targetHash) { throw 'Контрольная сумма собранного архива не совпала.' }
    } finally { $reader.Dispose() }
}
if ($Action -eq 'Uninstall') {
    if (-not (Test-Path -LiteralPath $statePath)) { throw 'Не найдена запись установки этого русификатора.' }
    $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in $state.files) {
        $targetPath=Target $file.target
        if (-not (Test-Path -LiteralPath $targetPath) -or (Hash $targetPath) -ne $file.installed) { throw "Файл $($file.target) изменён после установки. Удаление остановлено." }
        if ($file.existed -and ((Hash (Join-Path $backupRoot $file.backup)) -ne $file.original)) { throw "Резервная копия $($file.target) повреждена." }
    }
    $work=Join-Path $GamePath ('.slowdamage-rus-restore-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    $changed=@()
    try {
        foreach ($file in $state.files) { Copy-Item -LiteralPath (Target $file.target) -Destination (Join-Path $work $file.backup) }
        foreach ($file in $state.files) {
            $changed+=,$file
            if ($file.existed) { Copy-Item -LiteralPath (Join-Path $backupRoot $file.backup) -Destination (Target $file.target) -Force }
            else { Remove-Item -LiteralPath (Target $file.target) }
        }
    } catch {
        foreach ($file in $changed) { Copy-Item -LiteralPath (Join-Path $work $file.backup) -Destination (Target $file.target) -Force }
        throw
    } finally {
        foreach ($file in $state.files) { $p=Join-Path $work $file.backup; if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p} }
        Remove-Item -LiteralPath $work
    }
    # Retain the original backups; remove only the installation marker.
    Remove-Item -LiteralPath $statePath
    Write-Output 'Русификатор удалён. Предыдущие файлы восстановлены. Сохранения игры оставлены на месте.'
    exit 0
}
if (Test-Path -LiteralPath $statePath) {
    $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in $state.files) {
        if ((Hash (Target $file.target)) -ne $file.installed) { throw 'Установленные файлы изменены. Проверьте резервные копии перед переустановкой.' }
    }
    Write-Output 'Эта версия русификатора уже установлена.';exit 0
}
$plan=@();$index=0
foreach ($file in $manifest.files) {
    $targetPath=Target $file.target;$exists=Test-Path -LiteralPath $targetPath
    $current=if($exists){Hash $targetPath}else{$null}
    $delta=$null
    if ($file.complete) {
        if ($exists) { throw "Файл $($file.target) уже существует. Установка остановлена для сохранения другого мода." }
        $payload=Join-Path $packageRoot ('payload/'+$file.complete)
        if ((Hash $payload) -ne $file.hash) { throw 'Файл стартового экрана повреждён.' }
    } else {
        if (-not $exists) { throw 'Сначала установите английский Slow Damage Fan Patch (_base2.npk в папке patch).' }
        $variant=@($file.variants | Where-Object { $_.source -eq $current })
        if ($variant.Count -ne 1) { throw "Архив $($file.target) не поддерживается. Нужен JAST USA 1.10 с английским Fan Patch." }
        $delta=Join-Path $packageRoot ('payload/'+$variant[0].name)
        if ((Hash $delta) -ne $variant[0].hash) { throw 'Файл изменений повреждён.' }
    }
    $plan+=,[PSCustomObject]@{target=$file.target;existed=$exists;original=$current;installed=$file.hash;backup=([string]$index+'.npk');delta=$delta;complete=$file.complete}
    $index++
}
$work=Join-Path $GamePath ('.slowdamage-rus-work-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$changed=@();$createdBackups=@();$success=$false
try {
    foreach ($file in $plan) {
        $staged=Join-Path $work $file.backup
        if ($file.delta) { Apply-Delta (Target $file.target) $file.delta $staged }
        else { Copy-Item -LiteralPath (Join-Path $packageRoot ('payload/'+$file.complete)) -Destination $staged }
        if ((Hash $staged) -ne $file.installed) { throw 'Контрольная сумма результата не совпала.' }
    }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    foreach ($file in $plan) {
        if ($file.existed) {
            $backup=Join-Path $backupRoot $file.backup
            if (Test-Path -LiteralPath $backup) {
                if ((Hash $backup) -ne $file.original) { throw 'Найдена резервная копия от другой установки. Она не будет перезаписана.' }
            } else { Copy-Item -LiteralPath (Target $file.target) -Destination $backup;$createdBackups+=,$backup }
            if ((Hash $backup) -ne $file.original) { throw 'Ошибка проверки резервной копии.' }
        }
    }
    foreach ($file in $plan) {
        # Detect external changes between preflight and replacement.
        if ($file.existed -and (Hash (Target $file.target)) -ne $file.original) { throw 'Архив изменился во время установки.' }
        if (-not $file.existed -and (Test-Path -LiteralPath (Target $file.target))) { throw 'Целевой файл появился во время установки.' }
        $changed+=,$file
        Copy-Item -LiteralPath (Join-Path $work $file.backup) -Destination (Target $file.target) -Force
        if ((Hash (Target $file.target)) -ne $file.installed) { throw 'Не удалось проверить установленный файл.' }
        Write-Output ($file.target+' — готово.')
    }
    [PSCustomObject]@{version=$manifest.version;files=$plan}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statePath -Encoding UTF8
    $success=$true
} catch {
    foreach ($file in $changed) {
        if ($file.existed) { Copy-Item -LiteralPath (Join-Path $backupRoot $file.backup) -Destination (Target $file.target) -Force }
        elseif(Test-Path -LiteralPath (Target $file.target)){Remove-Item -LiteralPath (Target $file.target)}
    }
    if(Test-Path -LiteralPath $statePath){Remove-Item -LiteralPath $statePath}
    foreach($backup in $createdBackups){Remove-Item -LiteralPath $backup}
    throw
} finally {
    foreach ($file in $plan) { $p=Join-Path $work $file.backup;if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p} }
    Remove-Item -LiteralPath $work
}
if($success){Write-Output 'Русский перевод v0.1.0 установлен. Можно запускать игру.'}
