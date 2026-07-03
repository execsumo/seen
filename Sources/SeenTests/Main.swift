import Foundation

@main
struct SeenTestsMain {
    static func main() async {
        var passed = 0
        var failures: [(name: String, error: String)] = []

        for test in allTests {
            do {
                try await test.body()
                passed += 1
                print("PASS \(test.name)")
            } catch {
                failures.append((test.name, String(describing: error)))
                print("FAIL \(test.name)\n     \(error)")
            }
        }

        print("\n\(passed) passed, \(failures.count) failed, \(allTests.count) total")
        exit(failures.isEmpty ? 0 : 1)
    }
}
