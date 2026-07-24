# Changelog

## [0.1.0] - 2026-07-24

- Added startup and manual checks for newly published AvatarRecovery versions.
- Added Japanese and English notifications with installed/latest version information.
- Added manual update guidance for VCC and ALCOM.
- Kept the notifier independent from AvatarRecovery and compatible with older installed versions.
- Kept project packages and assets unchanged; automatic package updates are not included.
- Prevented overlapping Unity Editor sessions from showing or suppressing an outdated notification.
- Retried sooner when update-check state could not be saved, instead of waiting 24 hours.
- Kept update checks reliable after large changes to the system clock.
- Prevented a failed schedule save from delaying the next automatic check.
- Prevented another Unity project from making the Editor wait while notifier state was busy.
- Prevented closing Unity from being treated as dismissing an update notification.
- Preserved the later check schedule when concurrent state saves used the same verified release.
