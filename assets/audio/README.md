# Alarm audio asset

The `alarm` package v3.x requires a non-empty `assetAudioPath` even when
you only want the OS notification to ring. Drop your alarm sound here
as `alarm.mp3` (or change `defaultAudioAsset` in
`lib/services/alarm_service.dart` to point at any other asset you ship).