# Reference images

One folder per snapshot test class, one PNG per screen and state, named
`<test>.<state>.png`. They are recorded on CI's `app` job (macOS 26, Xcode 26.3), never on a
developer's Mac, and committed from that job's `snapshots` artifact
(`scripts/snapshot-references.sh <run id>` copies the new ones here). A test with no reference
fails and writes one, so a new screen's first run is red until its image is reviewed and
committed. See `App/Tests/Snapshots/ScreenSnapshotCase.swift`.
