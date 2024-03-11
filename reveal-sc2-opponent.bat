start powershell ^
-NoExit ^
-ExecutionPolicy bypass ^
-C "./Reveal-Sc2Opponent.ps1" ^
-DisableQuickEdit ^
-FilePath opponent.txt ^
-RatingFormat long ^
-RaceFormat short ^
-SelectProfile ^
-Limit 3
