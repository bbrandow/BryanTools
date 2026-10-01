# Monitor Controls Attribution

The DDC transport and display-service matching in `MonitorHardware` and
`MonitorControlCore` are adapted from MonitorControl's `Arm64DDC.swift`,
`IntelDDC.swift`, and private API declarations at commit
`84ac2d72bfb53b653536e484946f6ed027e4229c`:
https://github.com/MonitorControl/MonitorControl

Copyright MonitorControl contributors, including @JoniVR, @theOneyouseek,
@waydabber and @reitermarkus. The MIT license is included here and in the app bundle.
Bryan Tools adds runtime symbol checks, reply validation, explicit IOKit handle
cleanup, conservative matching, background discovery/writes, and a bounded write queue.

Media-key decoding and the dedicated brightness key codes follow MediaKeyTap:
https://github.com/MonitorControl/MediaKeyTap
Copyright (c) 2016 Nicholas Hurden. Its MIT license is also included.

No external application or runtime download is required. This integration does
not include MonitorControl's UI, software dimming, gamma changes, or OSD helpers.
