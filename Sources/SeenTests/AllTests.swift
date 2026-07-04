// Every suite must be registered here — one line per test file's array.
// Workstreams append their own suites (do not remove existing ones).
let allTests: [TestCase] =
    domainTests
    + coreEngineTests
    + shellTests
