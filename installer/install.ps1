param([Parameter(Mandatory=$true)][ValidateSet('Install','Uninstall')][string]$Action,
      [Parameter(Mandatory=$true)][string]$GamePath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$GamePath=[IO.Path]::GetFullPath($GamePath)
if(-not(Test-Path -LiteralPath (Join-Path $GamePath 'slow_damage_en.exe'))){throw 'В выбранной папке нет slow_damage_en.exe.'}
if(Get-Process -Name slow_damage_en -ErrorAction SilentlyContinue){throw 'Закройте игру перед установкой или удалением перевода.'}
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$backupRoot=Join-Path $GamePath '.slowdamage-rus-backup'
$statePath=Join-Path $backupRoot 'installed.json'
function Hash([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Target([string]$relative){
    $resolved=[IO.Path]::GetFullPath((Join-Path $GamePath $relative))
    if(-not $resolved.StartsWith($GamePath.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Некорректный путь в манифесте.'}
    $resolved
}
function Clear-Work([string]$work){
    foreach($file in Get-ChildItem -LiteralPath $work -File){Remove-Item -LiteralPath $file.FullName}
    Remove-Item -LiteralPath $work
}
function Apply-Delta([string]$original,[string]$delta,[string]$destination){
    Copy-Item -LiteralPath $original -Destination $destination
    $reader=New-Object IO.BinaryReader ([IO.File]::OpenRead($delta))
    try{
        if([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'DMP1'){throw 'Повреждён файл изменений.'}
        $sourceSize=$reader.ReadInt64();$targetSize=$reader.ReadInt64()
        $sourceHash=([BitConverter]::ToString($reader.ReadBytes(32))).Replace('-','').ToLowerInvariant()
        $targetHash=([BitConverter]::ToString($reader.ReadBytes(32))).Replace('-','').ToLowerInvariant()
        $count=$reader.ReadInt32()
        if((Get-Item -LiteralPath $original).Length -ne $sourceSize -or (Hash $original) -ne $sourceHash){throw 'Исходный архив отличается от поддерживаемого.'}
        if($targetSize -lt 0 -or $count -lt 0 -or $count -gt 100000){throw 'Некорректный заголовок изменений.'}
        $stream=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Write)
        try{
            $stream.SetLength($targetSize)
            for($i=0;$i -lt $count;$i++){
                $offset=$reader.ReadInt64();$size=$reader.ReadInt32()
                if($offset -lt 0 -or $size -lt 0 -or $size -gt 1048576 -or $offset+$size -gt $targetSize){throw 'Некорректный блок изменений.'}
                $bytes=$reader.ReadBytes($size)
                if($bytes.Length -ne $size){throw 'Файл изменений обрезан.'}
                $stream.Position=$offset;$stream.Write($bytes,0,$bytes.Length)
            }
            if($reader.BaseStream.Position -ne $reader.BaseStream.Length){throw 'Лишние данные в файле изменений.'}
        }finally{$stream.Dispose()}
        if((Hash $destination) -ne $targetHash){throw 'Контрольная сумма собранного архива не совпала.'}
    }finally{$reader.Dispose()}
}
$oldState=$null
if(Test-Path -LiteralPath $statePath){
    $oldState=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
    $expected=@($manifest.files|ForEach-Object{$_.target})
    if($oldState.files.Count -ne $expected.Count){throw 'Некорректная запись предыдущей установки.'}
    $seen=@()
    foreach($file in $oldState.files){
        if($file.target -notin $expected -or $file.target -in $seen -or $file.backup -notmatch '^\d+\.npk$'){throw 'Некорректная запись предыдущей установки.'}
        $seen+=,$file.target
        $targetPath=Target $file.target
        if(-not(Test-Path -LiteralPath $targetPath) -or (Hash $targetPath) -ne $file.installed){throw "Файл $($file.target) изменён после установки. Операция остановлена."}
        if($file.existed -and (Hash (Join-Path $backupRoot $file.backup)) -ne $file.original){throw "Резервная копия $($file.target) повреждена."}
    }
    foreach($directory in $oldState.createdDirectories){if($directory -ne 'patch'){throw 'Некорректная запись папок установки.'}}
}
if($Action -eq 'Uninstall'){
    if(-not $oldState){throw 'Не найдена запись установки русификатора.'}
    $work=Target ('.slowdamage-rus-restore-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work|Out-Null
    $changed=@()
    try{
        foreach($file in $oldState.files){Copy-Item -LiteralPath (Target $file.target) -Destination (Join-Path $work $file.backup)}
        foreach($file in $oldState.files){
            $changed+=,$file
            if($file.existed){Copy-Item -LiteralPath (Join-Path $backupRoot $file.backup) -Destination (Target $file.target) -Force}
            else{Remove-Item -LiteralPath (Target $file.target)}
        }
        Remove-Item -LiteralPath $statePath
    }catch{
        foreach($file in $changed){Copy-Item -LiteralPath (Join-Path $work $file.backup) -Destination (Target $file.target) -Force}
        throw
    }finally{Clear-Work $work}
    foreach($directory in $oldState.createdDirectories){
        $path=Target $directory
        if((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0){Remove-Item -LiteralPath $path}
    }
    Write-Output 'Русификатор удалён. Файлы до первой установки восстановлены. Сохранения оставлены на месте.'
    exit 0
}
foreach($required in $manifest.requirements){
    $path=Target $required.target
    if(-not(Test-Path -LiteralPath $path) -or (Hash $path) -ne $required.hash){throw "Архив $($required.target) не соответствует поддерживаемой JAST USA 1.10."}
}
if($oldState -and $oldState.version -eq $manifest.version){
    foreach($file in $manifest.files){if((Hash (Target $file.target)) -ne $file.hash){throw 'Установленная версия не соответствует манифесту.'}}
    Write-Output ('Русификатор v'+$manifest.version+' уже установлен.');exit 0
}
$plan=@();$index=0
foreach($file in $manifest.files){
    $path=Target $file.target;$exists=Test-Path -LiteralPath $path
    $before=if($exists){Hash $path}else{$null};$delta=$null
    if($file.complete){
        if($exists -and $before -notin $file.sources){throw "Файл $($file.target) изменён неизвестным модом. Он не будет перезаписан."}
        $payload=Join-Path $PSScriptRoot ('payload/'+$file.complete)
        if((Hash $payload) -ne $file.hash){throw 'Архив русификатора повреждён.'}
    }else{
        if(-not $exists){throw "Не найден $($file.target). Выберите папку установленной игры."}
        $variants=@($file.variants|Where-Object{$_.source -eq $before})
        if($variants.Count -ne 1){throw "Архив $($file.target) не соответствует поддерживаемой версии игры."}
        $delta=Join-Path $PSScriptRoot ('payload/'+$variants[0].name)
        if((Hash $delta) -ne $variants[0].hash){throw 'Файл изменений повреждён.'}
    }
    $previous=if($oldState){@($oldState.files|Where-Object{$_.target -eq $file.target})[0]}else{$null}
    $plan+=,[PSCustomObject]@{target=$file.target;existed=$(if($previous){$previous.existed}else{$exists});
        original=$(if($previous){$previous.original}else{$before});installed=$file.hash;
        backup=$(if($previous){$previous.backup}else{[string]$index+'.npk'});
        before=$before;beforeExists=$exists;delta=$delta;complete=$file.complete;index=$index}
    $index++
}
$work=Target ('.slowdamage-rus-work-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work|Out-Null
$changed=@();$createdBackups=@();$createdDirectories=@()
if($oldState){$createdDirectories=@($oldState.createdDirectories|Where-Object{$_})}
try{
    if($oldState){Copy-Item -LiteralPath $statePath -Destination (Join-Path $work 'installed.json')}
    foreach($file in $plan){
        $staged=Join-Path $work ('after-'+$file.index+'.npk')
        if($file.delta){Apply-Delta (Target $file.target) $file.delta $staged}
        else{Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('payload/'+$file.complete)) -Destination $staged}
        if((Hash $staged) -ne $file.installed){throw 'Контрольная сумма результата не совпала.'}
        if($file.beforeExists){
            $rollback=Join-Path $work ('before-'+$file.index+'.npk')
            Copy-Item -LiteralPath (Target $file.target) -Destination $rollback
            if((Hash $rollback) -ne $file.before){throw 'Файл изменился во время подготовки установки.'}
        }
    }
    New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null
    foreach($file in $plan){
        if($file.existed){
            $backup=Join-Path $backupRoot $file.backup
            if(Test-Path -LiteralPath $backup){if((Hash $backup) -ne $file.original){throw 'Найдена резервная копия другой установки. Она не будет перезаписана.'}}
            else{Copy-Item -LiteralPath (Target $file.target) -Destination $backup;$createdBackups+=,$backup}
            if((Hash $backup) -ne $file.original){throw 'Ошибка проверки резервной копии.'}
        }
    }
    $patchDirectory=Target 'patch'
    if(-not(Test-Path -LiteralPath $patchDirectory)){New-Item -ItemType Directory -Path $patchDirectory|Out-Null;$createdDirectories+=,'patch'}
    foreach($file in $plan){
        $path=Target $file.target
        if($file.beforeExists -and (Hash $path) -ne $file.before){throw 'Файл изменился во время установки.'}
        if(-not $file.beforeExists -and (Test-Path -LiteralPath $path)){throw 'Целевой файл появился во время установки.'}
        $changed+=,$file
        Copy-Item -LiteralPath (Join-Path $work ('after-'+$file.index+'.npk')) -Destination $path -Force
        if((Hash $path) -ne $file.installed){throw 'Ошибка проверки установленного файла.'}
        Write-Output ($file.target+' — готово.')
    }
    [PSCustomObject]@{version=$manifest.version;files=$plan;createdDirectories=$createdDirectories}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $statePath -Encoding UTF8
}catch{
    foreach($file in $changed){
        if($file.beforeExists){Copy-Item -LiteralPath (Join-Path $work ('before-'+$file.index+'.npk')) -Destination (Target $file.target) -Force}
        elseif(Test-Path -LiteralPath (Target $file.target)){Remove-Item -LiteralPath (Target $file.target)}
    }
    if($oldState){Copy-Item -LiteralPath (Join-Path $work 'installed.json') -Destination $statePath -Force}
    elseif(Test-Path -LiteralPath $statePath){Remove-Item -LiteralPath $statePath}
    foreach($backup in $createdBackups){Remove-Item -LiteralPath $backup}
    foreach($directory in $createdDirectories){
        if($oldState -and $directory -in $oldState.createdDirectories){continue}
        $path=Target $directory
        if((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0){Remove-Item -LiteralPath $path}
    }
    throw
}finally{Clear-Work $work}
Write-Output ('Русский перевод v'+$manifest.version+' установлен. Можно запускать игру.')
