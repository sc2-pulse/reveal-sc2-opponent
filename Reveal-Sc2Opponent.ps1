
<#PSScriptInfo

.VERSION 0.2.1

.GUID db8ffc68-4388-4119-b437-1f56c999611e

.AUTHOR nephestdev@gmail.com

.COMPANYNAME 

.COPYRIGHT 

.TAGS 

.LICENSEURI https://github.com/sc2-pulse/reveal-sc2-opponent/blob/main/LICENSE.txt

.PROJECTURI https://github.com/sc2-pulse/reveal-sc2-opponent

.ICONURI https://sc2pulse.nephest.com/sc2/static/icon/misc/favicon-32.png

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES


#>

<# 

.DESCRIPTION 
 Reveals ranked 1v1 opponent names for StarCraft2 

#> 
param(
    [Parameter(Mandatory=$true)]
    [int64[]]$CharacterId,
    [ValidateSet("terran", "protoss", "zerg", "random")]
    [string]$Race,
    [ValidateRange(1, 10)]
    [int32]$Limit = 3,
    [ValidateRange(1, 10000)]
    [int32]$RatingDeltaMax = 1000,
    [ValidateRange(1, [int32]::MaxValue)]
    [int32]$LastPlayedAgoMax = 2400,
    [ValidateSet("us", "eu", "kr", "cn")]
    [string[]]$ActiveRegion = @("us", "eu", "kr"),
    [string]$FilePath,
    [switch]$Notification,
    [switch]$Test
)

Test-ScriptFileInfo $PSCommandPath
<#
    .quickedit
    disable console quick edit mode to prevent the user from accidentally
    pausing the script by clicking on it
#>
Add-Type -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int mode);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetStdHandle(int handle);
"@ -Namespace Win32 -Name NativeMethods
$Handle = [Win32.NativeMethods]::GetStdHandle(-10)
[Win32.NativeMethods]::SetConsoleMode($Handle, 0x0080)
Write-Verbose "Disabled console quick edit"

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
if(-not [string]::IsNullOrEmpty($Race)) { $Race = $Race.ToUpper() }
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
    Finished = $true
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
    $Finished = $Game -eq $null -or
        $Game.Players.Length -eq 0 -or
        $Game.ActivePlayerCount -le $Game.Players.Length / 2
    Add-Member -InputObject $Game -Name Finished -Value $Finished -MemberType NoteProperty
    $Status = if($Game.Players.Length -eq 0) {
        [GameStatus]::None
    } else { 
        if($Game.isReplay -or
            ($Game.Players | Where {$_.type -eq "user"} | Measure-Object).Count -ne $ValidPlayerCount) {
                [GameStatus]::Unsupported
        } else {
            if(-not $CurrentGame.isReplay -and
                $Game.Players.Length -eq $CurrentGame.Players.Length -and
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


function Get-Team {
    param(
        [int32] $Season,
        [string] $Race,
        [string] $Queue,
        [int64[]] $CharacterId
    )
    $CharacterTeams = @()
    for(($i = 0); $i -lt $CharacterId.Length;)
    {
        $EndIx = [Math]::Min($i + $Script:TeamBatchSize - 1, $CharacterId.Length - 1);
        $CharacterIdBatch = $CharacterId[$i..$EndIx]
        $CharacterTeamBatch = Invoke-EnhancedRestMethod -Uri ("${Sc2PulseApiRoot}/group/team" +
            "?season=${Season}" +
            "&queue=${Queue}" +
            "&race=${Race}" +
            "&characterId=$([String]::Join(',', $CharacterIdBatch))")
        $CharacterTeams += $CharacterTeamBatch
        $i += $Script:TeamBatchSize
    }
    return $CharacterTeams
}

function Get-TeamMemberRace {
    param([Object] $TeamMember)

    $Race = $null
    $Games = 0
    foreach($CurRace in $Script:Races.Values) {
        $CurGames = $TeamMember."${CurRace}GamesPlayed"
        if($CurGames -gt $Games) {
            $Race = $CurRace
            $Games = $CurGames
        }
    }
    return $Race
}

function Get-TeamRace {
    param([Object] $Team)

    if($Team.Members.Length -ne 1) {
        return $null
    }
    return Get-TeamMemberRace $Team.Members[0]
}

function Get-UnmaskedPlayer {
    param(
        [Object] $PlayerTeam,
        [Object] $GameOpponent,
        [int32] $Season,
        [string] $Race,
        [string] $Queue,
        [int32] $LastPlayedAgoMax,
        [int32] $RatingDeltaMax,
        [int32] $Limit
    )
    $SearchActivity = "Opponent search"
    Write-Host ("Searching for ${Region} $($Races[$GameOpponent.Race]) $($GameOpponent.Name)" +
        ", $([Math]::Max($PlayerTeam.rating - $RatingDeltaMax, 0))" +
        "-$([Math]::Max($PlayerTeam.rating + $RatingDeltaMax, 0)) MMR" +
        ", up to ${Limit} closest matches")
    Write-Progress `
        -Activity $SearchActivity `
        -Status "Searching for opponents" `
        -PercentComplete 0
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
    Write-Progress `
        -Activity $SearchActivity `
        -Status "Pulling opponent teams" `
        -PercentComplete 40
    $OpponentTeams = Get-Team `
        -Season $Season `
        -Queue $Queue `
        -Race $Script:Races[$GameOpponent.Race] `
        -CharacterId $OpponentIds
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

    $CloseOpponentTeams = $OpponentTeams | Where-Object { $_.RatingDelta -le $RatingDeltaMax }
    $ActiveOpponentTeams = $CloseOpponentTeams | Where-Object { $_.LastPlayedAgo -le $LastPlayedAgoMax }
    $FinalOpponentTeams = if($ActiveOpponentTeams.Length -eq 0 -and
        $CloseOpponentTeams.Length -le $Limit) {
            $CloseOpponentTeams
    } else {
        $ActiveOpponentTeams
    }
    $UnmaskedPlayers = $FinalOpponentTeams |
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

function Get-PlayerProfile {
    param(
        [int32[]]$Season,
        [string]$Queue,
        [int64[]]$CharacterId,
        [string]$OverrideRace
    )

    $PlayerTeams = @()
    foreach($CurSeasonId in $Season) {
        $PlayerTeams += (Get-Team -Season $CurSeasonId -CharacterId $CharacterId -Queue $Queue)
    }
    if($PlayerTeams.Length -eq 0) { return $null; }
    $Now = [DateTimeOffset]::Now
    foreach($Team in $PlayerTeams) {
        $LastPlayedParsed = [DateTimeOffset]::Parse(
            $Team.LastPlayed,
            $null,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
        $LastPlayedAgo = $Now.Subtract($LastPlayedParsed).TotalSeconds
        Add-Member -InputObject $Team -Name LastPlayedAgo -Value $LastPlayedAgo -MemberType NoteProperty
    }
    $RecentTeam = $PlayerTeams |
        Sort-Object -Property LastPlayedAgo |
        Select-Object -First 1
    $PlayerProfile = [PSCustomObject]@{
        Team = $RecentTeam
        Character = $RecentTeam.Members[0].Character
        CharacterName = $RecentTeam.Members[0].Character.Name.Substring(
            0, $RecentTeam.Members[0].Character.Name.IndexOf("#"))
        Season = $RecentTeam.Season
        Region = $RecentTeam.Region
        Race = Get-TeamRace $RecentTeam
    }
    if(-not [string]::IsNullOrEmpty($OverrideRace) -and
        $PlayerProfile.Race -ne $OverrideRace) {
        Write-Warning "Profile race has been overridden: $($PlayerProfile.Race)->$OverrideRace"
        $PlayerProfile.Race = $OverrideRace
    }
    return $PlayerProfile
}

if(-not [string]::IsNullOrEmpty($Race) -and $CharacterId.Length -gt 1) {
    Write-Warning "Using race override with multiple character ids"
} 
$Seasons = (Invoke-EnhancedRestMethod -Uri "${Sc2PulseApiRoot}/season/list/all") |
    Group-Object -Property Region -AsHashTable
$SeasonIds = $Seasons.Values |
    ForEach-Object { $_ | Select-Object -First 1 } |
    Where-Object {$ActiveRegion -contains $_.Region} |
    Select-Object -ExpandProperty BattlenetId -Unique
Write-Host "Active seasons: ${SeasonIds}"
$PlayerProfile =  Get-PlayerProfile `
    -Season $Script:SeasonIds `
    -Queue $Script:Queue1v1 `
    -CharacterId $Script:CharacterId `
    -OverrideRace $Script:Race
if($PlayerProfile -eq $null) {
    Write-Error "Can't find the reference team. Play at least 1 ranked game and wait for several minutes."
    return 10
}
Write-Host $PlayerProfile
Write-Host "Script loaded, waiting for games"
while($true) {
    $Game = Get-Game `
        -CurrentGame $Script:CurrentGame `
        -ValidPlayerCount $Script:ValidPlayerCount
    if(-not [string]::IsNullOrEmpty($FilePath) -and
        $Game -ne $null -and (
            ($Game.Status -eq [GameStatus]::Unsupported -and
                $Game.Status -ne $CurrentGame.Status) -or
            ($Game.Finished -and -not $CurrentGame.Finished)
        ) -and
        (Test-Path -Path $FilePath)) {
            Clear-Content -Path $FilePath
            Write-Verbose "Cleared $FilePath"
    }
    $Script:CurrentGame = $Game
    if($Script:CurrentGame.Status -eq [GameStatus]::New) {
        Write-Host "New game detected"
        $PlayerProfile  = Get-PlayerProfile `
            -Season $Script:SeasonIds `
            -Queue $Script:Queue1v1 `
            -CharacterId $Script:CharacterId `
            -OverrideRace $Script:Race
        Write-Host "Using profile ${PlayerProfile}"
        $Opponent = Get-Opponent `
            -PlayerName $PlayerProfile.CharacterName `
            -PlayerRace $PlayerProfile.Race `
            -Player $Script:CurrentGame.Players
        if($Script:Test) { $Opponent.name = 'llllllllllll' } 
        $UnmaskedPlayers = (Get-UnmaskedPlayer `
            -GameOpponent $Opponent `
            -Season $PlayerProfile.Season `
            -Race $PlayerProfile.Race `
            -Queue $Script:Queue1v1 `
            -PlayerTeam $PlayerProfile.Team `
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
