# AvatarRecovery Update Notifier

AvatarRecovery Update Notifier is a standalone Unity Editor add-on that notifies you when a new version of AvatarRecovery is available.

It only displays update information and opens the official manual update guide. It never downloads or installs packages, modifies `Packages` or `Assets`, closes Unity, or launches an external package manager.

## Install

- VCC or ALCOM: [Open the install page](https://nickel-jp.github.io/avatar-recovery-updater-unity/) and select **Add to VCC / ALCOM**.
- Manual setup: Open the VPM repository manager and add the repository URL below.
- VPM repository URL: `https://nickel-jp.github.io/avatar-recovery-updater-unity/index.json`

After adding the repository, add `AvatarRecovery Update Notifier` to a project that already contains AvatarRecovery.

## Requirements

- Unity 2022.3.x
- AvatarRecovery installed as `com.nickel-jp.avatar-recovery`

If AvatarRecovery is not installed, automatic checks do not make a network request.

## Network and privacy

After a successful startup check, the notifier waits 24 hours before checking again in that Unity project. If a check fails, it may retry after 30 minutes.

- Check now: `Tools > Nickel-JP > AvatarRecovery Update Notifier > Check Now`
- Settings: `Tools > Nickel-JP > AvatarRecovery Update Notifier > Settings`

No telemetry or project content is transmitted.

## Update behavior

When a newer version is available, the notifier shows both the installed version and the latest available version. You must install updates manually through VCC or ALCOM.

If a network check fails, the project continues to work normally and the notifier retries later. Offline use does not modify the project.

## Links

- [Update guide](https://nickel-jp.github.io/avatar-recovery-updater-unity/update/)
- [AvatarRecovery](https://github.com/Nickel-JP/avatar-recovery-unity)
- [AvatarRecovery Community Server](https://discord.gg/M9nFq8HXv)

## License

Use and local modification are permitted only for personal, private, or internal projects. Redistribution, publication, sale, sublicensing, and integration into another public tool or package require written permission from the copyright holder.

See [LICENSE](LICENSE) for the controlling terms.
