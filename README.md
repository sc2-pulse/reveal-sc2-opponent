# reveal-sc2-opponent
reveal-sc2-opponent is a Windows PowerShell script that reveals well-known tags or BattleTags and MMR of your ranked 1v1 opponents via the StarCraft2 game client and [SC2 Pulse](https://github.com/sc2-pulse/sc2-pulse) APIs. Requires Windows 10+.

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
* SC2 Pulse is about 5 minutes behind, and revealed data is provided by SC2 Pulse editors, so the data is approximate and may be invalid. This also means that active profiles are not detected instantly when you switch an account, region, or race.
* Windows console doesn't support asian glyphs by default. If you use the console and want to see glyphs, then you need to change the default font to `MS Gothic`. RMB on the console header->Defaults->Font.
* When using Windows notifications for the first time, Windows will ask you for emergency notification permission for this script. You must allow it. Emergency notifications are always on top of everything else, otherwise notifications will be created but you won't see them because they will be below the SC2 game client window. Make sure the `Get notifications from apps and other senders` option is enabled in `Notification & Actions` section of your Windows settings.

## Security/ToS
The script uses the SC2 client API http://localhost:6119/game which is an official API added by Blizzard for streamers http://web.archive.org/web/20160818015235/https://us.battle.net/forums/en/sc2/topic/20748195420

No dangerous techniques is used, such as: datamining, packet sniffing, memory reading, render hooks. The script only calls the web API endpoints, that's it. It doesn't interact with the game client in an unintended way and doesn't render anything on top of it. No data about the game itself is provided. No unfair advantage is given to any player.

The SC2 client data is then combined with the SC2 Pulse data. SC2 Pulse follows the Blizzard ToS, including the 30 day privacy policy, so its data is valid and safe to use. The project doesn't track previous names and BattleTags and only links well-known profiles to famous players and streamers to improve user experience.

There is no intention of revealing any private data that can be used to identify a real person, excluding public information of pro players from public sources such as liquipedia. All data is related to the game and is used to enhance player experience.

Furthermore,  this is not a new idea. There have been such scripts and overlays in the past and people used them without any problems. Those projects relied on sc2unmasked API which is no longer available, so it's just reiteration of the old ideas.

Considering all of the above it should be safe to use as it doesn't violate any rules. Of course no one can guarantee anything which is reflected in the script license, use it at your own risk. Blizzard can do whatever they want, the ToS is just a guideline, they can close any project if they think it harms their business, even if the project follows their ToS. The general guideline for community projects is that they must improve player experience and this script was designed to do just that.

## Running
Download script files(.bat and .ps1) to the same directory. Run the `reveal-sc2-opponent.bat` script.
Depending on your security settings, Windows might prevent the script from running. Click `More info`->`Run anyway`. This Windows warning doesn't mean the script is dangerous, it just means that you downloaded the script from the internet and it's not signed by a trusted key, so Windows tries to protect you. Don't run such scripts if you don't trust their devs.

You need to provide a sc2pulse character id you will be playing. You can launch the script and provide the parameters manually every time, or you can add additional parameters to the `reveal-sc2-opponent.bat` script.

### SC2Pulse character id
* Find your profile here https://sc2pulse.nephest.com/sc2/?#search.
* Copy your profile id from the profile url. For example `https://www.nephest.com/sc2/?type=character&id=236695&m=1#player-stats-mmr`, copy the id parameter, in this case the id is `236695`.

### reveal-sc2-opponent.bat
Use this script to add parameters that rarely change(character id, race) or customize the opponent search algorithm. RMB->edit to edit. `-ParameterName parameterValue` or just `-ParameterName` for switch parameters.
Example:
```
start powershell ^
-NoExit ^
-ExecutionPolicy bypass ^
-C "./Reveal-Sc2Opponent.ps1" ^
-FilePath opponent.txt ^
-Limit 3 ^
-CharacterId 1,2,3,4,5
```

### Required parameters
* `CharacterId` SC2Pulse character ids, array.

### Output parameters
* `FilePath` Revealed opponents will be dumped into this file.
* `Notification` Switch parameter, enables Windows notifications.

### Opponent search parameters
`()` default value
* `RatingDeltaMax`(1000) Max MMR difference between you and your opponent
* `LastPlayedAgoMax`(2400) Seconds
* `Limit`(3) Opponent suggestion limit

### Misc parameters
* `Race` The race you will be playing, lower case. Overrides auto detected race from SC2 Pulse. Useful if you want to change an account/region/race but don't want to wait for SC2 Pulse to catch up.
* `DisableQuickEdit` Disable console `QuickEdit` mode. Prevents users from accidently pausing the script by clicking on the console window.
* `Test` Test mode for devs. Replaces your name with a barcode and allows you to test the script in a custom/vs ai game.
