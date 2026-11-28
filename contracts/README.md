# Contract fixtures (test data)

Recorded responses from the District AI API, copied unchanged from
[district-core-swift](https://github.com/distronode-corporation/district-core-swift)'s
`contracts/mobile` and `contracts/desktop` at the release `project.yml` pins DistrictCore to.
That repository's `ContractFixtureTests` holds its models to them, and the service's own test
suite generates them (see [mobile/README.md](mobile/README.md)).

Here they are only the data the screen snapshot tests (`App/Tests/Snapshots`) feed the app
through a fake transport, so each screen is drawn from the service's real answer rather than
a retyped one. They are not edited here: CI's `app` job fails unless both folders are byte for
byte the copies in the resolved DistrictCore package, so a core bump updates them in the same
pull request. Replace both folders rather than copying over them, so a fixture the core deleted
or renamed does not stay behind:

```sh
rm -rf contracts/mobile contracts/desktop
cp -R SourcePackages/checkouts/district-core-swift/contracts/{mobile,desktop} contracts/
```
