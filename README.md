# reveal-sc2-opponent
reveal-sc2-opponent is a Windows PowerShell script that reveals well-known tags or BattleTags of your ranked 1v1 opponents via the StarCraft2 game client and [SC2 Pulse](https://github.com/sc2-pulse/sc2-pulse) APIs. Requires Windows 10+.

## Use cases
* OBS: text source via file output.
* Multi monitor: console output.
* Single monitor: Windows notifications. Doesn't work in fullscreen mode. Requires windows 10+.

## Revealed info
The opponent's in-game tag will be replaced with the following info, sorted by priority.
* Revealed data from SC2 Pulse. Always used when available.
* BattleTag for barcodes
* In-game tag, possibly with unique discriminator(`#1234`)
* Original opponent name

## Limitations
* Ranked 1v1 only. Doesn't work with unranked opponents.
* Opponents who are playing their first game in last 40 minutes can't be detected.
* SC2 Pulse is about 5 minutes behind, and revealed data is provided by SC2 Pulse editors, so the data is approximate and may be invalid.
* Windows console doesn't support asian glyphs by default. If you use the console and want to see glyphs, then you need to change the default font to `MS Gothic`. RMB on the console header->Defaults->Font.

## Running
Download script files(.bat and .ps1) to the same directory. Run the `reveal-sc2-opponent.bat` script.
You need to provide a sc2pulse character id and a race you will be playing. You can launch the script and provide the parameters manually every time, or you can add additional parameters to the `reveal-sc2-opponent.bat` script.

### SC2Pulse character id
* Find your profile here https://sc2pulse.nephest.com/sc2/?#search.
* Copy your profile id from the profile url. For example `https://www.nephest.com/sc2/?type=character&id=236695&m=1#player-stats-mmr`, copy the id parameter, in this case the id is `236695`.

### reveal-sc2-opponent.bat
Use this script to add parameters that rarely change or customize the opponent search algorithm. RMB->edit to edit.

### Required parameters
* `CharacterId` SC2Pulse character id
* `Race` The race you will be playing, lower case.

### Output parameters
* `FilePath` Revealed opponents will be dumped into this file.
* `Notification` Switch parameter, enables Windows notifications.

### Opponent search parameters
`()` default value
* `RatingDeltaMax`(1000) Max MMR difference between you and your opponent
* `LastPlayedAgoMax`(2400) Seconds
* `Limit`(3) Opponent suggestion limit
