param(
    [Parameter(Mandatory=$true)]
    [int64]$CharacterId,
    [Parameter(Mandatory=$true)]
    [ValidateSet("terran", "protoss", "zerg", "random")]
    [string]$Race,
    [ValidateRange(1, 10)]
    [int32]$Limit = 3,
    [ValidateRange(1, 10000)]
    [int32]$RatingDeltaMax = 1000,
    [ValidateRange(1, [int32]::MaxValue)]
    [int32]$LastPlayedAgoMax = 2400,
    [string]$FilePath,
    [switch]$Notification,
    [switch]$Test
)

Add-Type -AssemblyName Microsoft.PowerShell.Commands.Utility
if($Test) { Write-Warning "Test mode" }

if(-not [string]::IsNullOrEmpty($FilePath)) {
    if(Test-Path -Path $FilePath) {
        Clear-Content -Path $FilePath
        Write-Verbose "Cleared $FilePath"
    } else {
        New-Item -Path $FilePath -ItemType File
        Write-Verbose "Created $FilePath"
    }
}

$Sc2PulseApiRoot = "https://sc2pulse.nephest.com/sc2/api"
$Sc2ClientApiRoot = "http://127.0.0.1:6119"
$Queue1v1 = "LOTV_1V1"
$ValidPlayerCount = if($Test) { 1 } else { 2 }
$Race = $Race.ToUpper()
$Races = @{
    Terr = "TERRAN"
    Prot = "PROTOSS"
    Zerg = "ZERG"
    random = "RANDOM"
}
enum GameStatus {
    New
    Old
    None
    Unsupported
}
$CurrentGame = [PSCustomObject]@{
    IsReplay = $false
    DisplayTime = 999999
    Players = @()
    ActivePlayerCount = 0
    Status = [GameStatus]::Old
}
if($Notification) {
    $Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $ToastAppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $ToastNotifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($ToastAppId)
}
$TeamBatchSize = 200

function Invoke-EnhancedRestMethod {
    param(
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get,
        [string]$Uri,
        [Object]$Body,
        [System.Text.Encoding]$Encoding = [system.Text.Encoding]::UTF8,
        [System.Net.HttpStatusCode[]]$ValidResponseCodes = @(
            [System.Net.HttpStatusCode]::OK,
            [System.Net.HttpStatusCode]::NotFound
        )
    )

    $ProgressPreference = 'SilentlyContinue';
    $Response = try {
        (Invoke-WebRequest -Method $Method -Uri $Uri -Body $Body)
    }  catch [System.Net.WebException] {
        if(-not ($ValidResponseCodes -contains $_.Exception.Response.StatusCode)) {
            throw $_.Exception
        }
    }
    $ProgressPreference = 'Continue';
    if([string]::IsNullOrEmpty($Response)) {
        return
    }
    return $Encoding.GetString($Response.RawContentStream.ToArray()) | ConvertFrom-Json
}

$Character = (Invoke-EnhancedRestMethod -Uri "${Sc2PulseApiRoot}/character/${CharacterId}")[0]
if($null -eq $Character) {
    Write-Error "Character ${CharacterId} not found"
    exit 1
}
$Region = $Character.Region
$CharacterName = $Character.Name.Substring(0, $Character.Name.IndexOf("#"))
Write-Host $Character
$Season = (Invoke-EnhancedRestMethod -Uri "${Sc2PulseApiRoot}/season/list/all") |
     Where-Object { $_.Region -eq $Region } |
     Select-Object -ExpandProperty BattlenetId -First 1
Write-Host "Season ${Season}"

function Is-Fake-Tag {
    param([string]$Tag)

    return $Tag.StartsWith("f#");
}

function Is-Barcode() {
    param([string]$PlayerName)

    return $PlayerName -match '^[IiLl]+#\d+$'
}

function Unmask-Player {
    param([Object]$Player)

    $UnmaskedPlayer = if([string]::IsNullOrEmpty($Player.ProNickname)) {
        if(-not (Is-Fake-Tag -Tag $Player.Account.BattleTag) -and
            (Is-Barcode -PlayerName $Player.Character.Name)) {
                $Player.Account.BattleTag
        } else {
            $Player.Character.Name
        }                
    } else {
        if(-not [string]::IsNullOrEmpty($Player.ProTeam)) {
            "[$($Player.ProTeam)]$($Player.ProNickname)"
        } else {
            $Player.ProNickname
        }
    }
    return $UnmaskedPlayer
}

function Get-Opponent {
    param(
        [string] $PlayerName,
        [string] $PlayerRace,
        [Object[]] $Player
    )
    
    foreach($CurPlayer in $Player) {
        if($CurPlayer.Type -eq "computer") {
            continue
        }
        if($CurPlayer.Name -cne $PlayerName) {
            return $CurPlayer
        }
        if(-not $PlayerRace.ToLower().startsWith($CurPlayer.Race.ToLower())) {
            return $CurPlayer
        }
    }
    return $Player[0]
}

function Get-Game {
    param(
        [Object] $CurrentGame,
        [int32] $ValidPlayerCount
    )

    try {
        $Game = Invoke-EnhancedRestMethod -Uri "${Sc2ClientApiRoot}/game" -IgnoreSocketException
    } catch [System.Net.WebException] {
        Write-Warning "SC2 client API not found. Launch the game."
        return
    }
    #SC2 client can return an empty result when launching
    if($Game -eq $null) {
        Write-Warning "SC2 client API not found. Launch the game."
        return
    }
    $ActivePlayerCount = ($Game.Players | Where {$_.result -eq "undecided"} | Measure-Object).Count
    Add-Member -InputObject $Game -Name ActivePlayerCount -Value $ActivePlayerCount -MemberType NoteProperty
    $Status = if($Game.Players.Length -eq 0) {
        [GameStatus]::None
    } else { 
        if($Game.isReplay -or
            ($Game.Players | Where {$_.type -eq "user"} | Measure-Object).Count -ne $ValidPlayerCount) {
                [GameStatus]::Unsupported
        } else {
            if($Game.Players.Length -eq $CurrentGame.Players.Length -and 
                $Game.DisplayTime -ge $CurrentGame.DisplayTime -and
                $Game.ActivePlayerCount -le $CurrentGame.ActivePlayerCount) {
                    [GameStatus]::Old
            } else {
                 [GameStatus]::New
            }            
        }
    }
    Add-Member -InputObject $Game -Name Status -Value $Status -MemberType NoteProperty
    return $Game
}

function Get-PlayerTeam {
    param(
        [int32] $Season,
        [string] $Race,
        [string] $Queue,
        [int64] $CharacterId,
        [int32] $Depth = 3
    )

    for(($i = 0); $i -lt $Depth; $i++) {
        $PlayerTeam = (Invoke-EnhancedRestMethod -Uri ("${Sc2PulseApiRoot}/group/team" +
            "?season=$($Season - $i)" +
            "&queue=${Queue}" +
            "&race=${Race}" +
            "&characterId=${CharacterId}"))
        if($PlayerTeam -ne $null -and $PlayerTeam.Length -eq 1) {
            return $PlayerTeam[0]
        }
    }
}

function Get-UnmaskedPlayer {
    param(
        [Object] $GameOpponent,
        [int32] $Season,
        [string] $Race,
        [string] $Queue,
        [int64] $CharacterId,
        [int32] $LastPlayedAgoMax,
        [int32] $RatingDeltaMax,
        [int32] $Limit
    )
    $SearchActivity = "Opponent search"
    Write-Progress `
        -Activity $SearchActivity `
        -Status "Pulling reference team" `
        -PercentComplete 0
    $PlayerTeam = Get-PlayerTeam `
        -Season $Season `
        -Race $Race `
        -Queue $Queue `
        -CharacterId $CharacterId
    if($PlayerTeam -eq $null) {
        Write-Error "Can't find the reference team. Play at least 1 ranked game and wait for several minutes."
        Write-Progress -Activity $SearchActivity -Status "Failed" -Completed
        return
    }
    Write-Host ("Searching for ${Region} $($Races[$GameOpponent.Race]) $($GameOpponent.Name)" +
        ", $([Math]::Max($PlayerTeam.rating - $RatingDeltaMax, 0))" +
        "-$([Math]::Max($PlayerTeam.rating + $RatingDeltaMax, 0)) MMR" +
        ", up to ${Limit} closest matches")
    Write-Progress `
        -Activity $SearchActivity `
        -Status "Searching for opponents" `
        -PercentComplete 10
    $OpponentIds = $(Invoke-EnhancedRestMethod -Uri ("${Sc2PulseApiRoot}/character/search/advanced" +
        "?season=${Season}" +
        "&region=${Region}" +
        "&queue=${Queue}" +
        "&name=$($GameOpponent.Name)" +
        "&caseSensitive=true"))
    if($OpponentIds.Length -eq 0) {
        Write-Progress -Activity $SearchActivity -Status "Failed" -Completed
        return
    }
    $OpponentTeams = @()
    Write-Progress `
        -Activity $SearchActivity `
        -Status "Pulling opponent teams" `
        -PercentComplete 40
    for(($i = 0); $i -lt $OpponentIds.Length;)
    {
        $EndIx = [Math]::Min($i + $Script:TeamBatchSize - 1, $OpponentIds.Length - 1);
        $OpponendIdBatch = $OpponentIds[$i..$EndIx]
        $OpponentTeamBatch = Invoke-EnhancedRestMethod -Uri ("${Sc2PulseApiRoot}/group/team" +
            "?season=${Season}" +
            "&queue=${Queue}" +
            "&race=$($Races[$GameOpponent.Race])" +
            "&characterId=$([String]::Join(',', $OpponendIdBatch))")
        $OpponentTeams += $OpponentTeamBatch
        $i += $Script:TeamBatchSize
        Write-Progress `
            -Activity "Opponent search" `
            -Status "Pulling opponent teams" `
            -PercentComplete (40 + (($EndIx / $OpponentIds.Length) * 60))
    }
    $Now = [DateTimeOffset]::Now
    foreach($Team in $OpponentTeams) {
        $LastPlayedParsed = [DateTimeOffset]::Parse(
            $Team.LastPlayed,
            $null,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
        $LastPlayedAgo = $Now.Subtract($LastPlayedParsed).TotalSeconds
        $RatingDelta = [Math]::Abs($Team.Rating - $PlayerTeam.Rating);
        Add-Member -InputObject $Team -Name LastPlayedAgo -Value $LastPlayedAgo -MemberType NoteProperty
        Add-Member -InputObject $Team -Name RatingDelta -Value $RatingDelta -MemberType NoteProperty
    }
     
    $UnmaskedPlayers = $OpponentTeams |
        Where-Object { $_.LastPlayedAgo -le $LastPlayedAgoMax -and 
            $_.RatingDelta -le $RatingDeltaMax } |
        Sort-Object -Property RatingDelta |
        Select-Object -First $Limit |
        ForEach-Object { Unmask-Player -Player $_.Members[0] }
    Write-Progress `
        -Activity "Opponent search" `
        -Status "Completed" `
        -PercentComplete 100 `
        -Completed
    return $($UnmaskedPlayers)
}

function Write-Toast {
    param(
        [Windows.UI.Notifications.ToastNotifier] $ToastNotifier,
        [string] $ToastText
    )
    $ToastXmlText = @"
<toast scenario='Urgent'>
    <visual>
        <binding template='ToastGeneric'>
            <text>${ToastText}</text>
        </binding>
    </visual>
</toast>
"@
    $ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
    $ToastXml.LoadXml($ToastXmlText)
    $ToastNotifier.Show($ToastXml)
}

function Write-All {
    param(
        [string] $Player,
        [string] $FilePath,
        [Windows.UI.Notifications.ToastNotifier] $ToastNotifier
    )
    Write-Output -InputObject $Player
    if(-not [string]::IsNullOrEmpty($FilePath)) {
        $Player | Out-File -FilePath $FilePath -Encoding utf8
        Write-Host "Saved to file ${FilePath}"
    }
    if($ToastNotifier -ne $null) {
        Write-Toast `
            -ToastNotifier $ToastNotifier `
            -ToastText $Player
    }
}

Write-Host "Script loaded, waiting for games"
while($true) {
    $Script:CurrentGame = Get-Game `
        -CurrentGame $Script:CurrentGame `
        -ValidPlayerCount $Script:ValidPlayerCount
    if($Script:CurrentGame.Status -eq [GameStatus]::New) {
        Write-Host "New game detected"
        $Opponent = Get-Opponent `
            -PlayerName $Script:CharacterName `
            -PlayerRace $Script:Race `
            -Player $Script:CurrentGame.Players
        if($Script:Test) { $Opponent.name = 'llllllllllll' } 
        $UnmaskedPlayers = (Get-UnmaskedPlayer `
            -GameOpponent $Opponent `
            -Season $Script:Season `
            -Race $Script:Race `
            -Queue $Script:Queue1v1 `
            -CharacterId $Script:CharacterId `
            -LastPlayedAgoMax $Script:LastPlayedAgoMax `
            -RatingDeltaMax $Script:RatingDeltaMax `
            -Limit $Script:Limit
        ) -join ", "
        if([string]::IsNullOrEmpty($UnmaskedPlayers)) {
            $UnmaskedPlayers = $Opponent.Name
            Write-Host $UnmaskedPlayers -ForegroundColor Red
        } else {
            Write-Host $UnmaskedPlayers -ForegroundColor Green
        }
        Write-All `
            -Player $UnmaskedPlayers `
            -FilePath $Script:FilePath `
            -ToastNotifier $Script:ToastNotifier
    }
    Start-Sleep -Seconds 1
}
