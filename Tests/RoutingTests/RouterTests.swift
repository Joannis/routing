import XCTest
import HTTP
import Branches
import Routing
import URI

extension String: Swift.Error {}

class RouterTests: XCTestCase {
    static let allTests = [
        ("testRouter", testRouter),
        ("testWildcardMethod", testWildcardMethod),
        ("testWildcardHost", testWildcardHost),
        ("testHostMatch", testHostMatch),
        ("testMiss", testMiss),
        ("testWildcardPath", testWildcardPath),
        ("testParameters", testParameters),
        ("testEmpty", testEmpty),
        ("testNoHostWildcard", testNoHostWildcard),
        ("testRouterDualSlugRoutes", testRouterDualSlugRoutes),
        ("testRouteLogs", testRouteLogs),
        ("testRouterThrows", testRouterThrows),
    ]

    func testRouter() throws {
        let router = Router()
        router.register(host: "0.0.0.0", method: .get, path: ["hello"]) { request in
            return Response(body: "Hello, World!")
        }

        let request = try Request(method: .get, uri: "http://0.0.0.0/hello")
        let response = try router.respond(to: request)
        XCTAssert(response.body.bytes?.makeString() == "Hello, World!")
    }

    func testWildcardMethod() throws {
        let router = Router()
        router.register(host: "0.0.0.0", method: .wildcard, path: ["hello"]) { request in
            return Response(body: "Hello, World!")
        }

        let method: [HTTP.Method] = [.get, .post, .put, .patch, .delete, .trace, .head, .options]
        try method.forEach { method in
            let request = try Request(method: method, uri: "http://0.0.0.0/hello")
            let response = try router.respond(to: request)
            XCTAssertEqual(response.body.bytes?.makeString(), "Hello, World!")
        }
    }

    func testWildcardHost() throws {
        let router = Router()
        router.register(host: "*", path: ["hello"]) { request in
            return Response(body: "Hello, World!")
        }

        let hosts: [String] = ["0.0.0.0", "chat.app.com", "[255.255.255.255.255]", "slack.app.com"]
        try hosts.forEach { host in
            let request = try Request(method: .get, uri: "http://\(host)/hello")
            let response = try router.respond(to: request)
            XCTAssertEqual(response.body.bytes?.makeString(), "Hello, World!")
        }
    }

    func testHostMatch() throws {
        let router = Router()

        let hosts: [String] = ["0.0.0.0", "chat.app.com", "[255.255.255.255.255]", "slack.app.com"]
        hosts.forEach { host in
            router.register(host: host, path: ["hello"]) { request in
                return Response(body: "Host: \(host)")
            }
        }

        try hosts.forEach { host in
            let request = try Request(method: .get, uri: "http://\(host)/hello")
            let response = try router.respond(to: request)
            XCTAssert(response.body.bytes?.makeString() == "Host: \(host)")
        }
    }

    func testMiss() throws {
        let router = Router()
        router.register(host: "0.0.0.0", method: .get, path: ["hello"]) { request in
            XCTFail("should not be found, wrong host")
            return "[fail]"
        }

        let request = try Request(method: .get, uri: "http://[255.255.255.255.255]/hello")
        let handler = router.route(request)
        XCTAssert(handler == nil)
    }

    func testWildcardPath() throws {
        let router = Router()
        router.register(host: "0.0.0.0", method: .get, path: ["hello", "*"]) { request in
            return "Hello, World!"
        }

        let paths: [String] = [
            "hello",
            "hello/zero",
            "hello/extended/path",
            "hello/very/extended/path.pdf"
        ]

        try paths.forEach { path in
            let request = try Request(method: .get, uri: "http://0.0.0.0/\(path)")
            let response = try router.respond(to: request)
            XCTAssert(response.body.bytes?.makeString() == "Hello, World!")
        }
    }

    func testParameters() throws {
        let router = Router()
        router.register(host: "0.0.0.0", method: .get, path: ["hello", ":name", ":age"]) { request in
            guard let name = request.parameters["name"]?.string else { throw "missing param: name" }
            guard let age = request.parameters["age"]?.int else { throw "missing or invalid param: age" }
            return "Hello, \(name) aged \(age)."
        }

        let namesAndAges: [(String, Int)] = [
            ("a", 12),
            ("b", 42),
            ("c", 200),
            ("d", 1)
        ]

        try namesAndAges.forEach { name, age in
            let request = try Request(method: .get, uri: "http://0.0.0.0/hello/\(name)/\(age)")
            let response = try router.respond(to: request)
            XCTAssertEqual(response.body.bytes?.makeString(), "Hello, \(name) aged \(age).")
        }
    }

    func testEmpty() throws {
        let router = Router()
        router.register(path: []) { request in
            return Response(body: "Hello, Empty!")
        }

        let empties: [String] = ["", "/"]
        try empties.forEach { emptypath in
            let uri = URI(scheme: "http", hostname: "0.0.0.0", path: emptypath)
            let request = Request(method: .get, uri: uri)
            let response = try router.respond(to: request)
            XCTAssertEqual(response.body.bytes?.makeString(), "Hello, Empty!")
        }
    }

    func testNoHostWildcard() throws {
        let router = Router()
        router.register { request in
            return Response(body: "Hello, World!")
        }

        let uri = URI(
            scheme: "",
            hostname: ""
        )
        let request = Request(method: .get, uri: uri)
        let response = try router.respond(to: request)
        XCTAssertEqual(response.body.bytes?.makeString(), "Hello, World!")
    }

    func testRouterDualSlugRoutes() throws {
        let router = Router()
        router.register(path: ["foo", ":a", "one"]) { _ in return "1" }
        router.register(path: ["foo", ":b", "two"]) { _ in return "2" }

        let requestOne = Request(method: .get, path: "foo/slug-val/one")
        let responseOne = try router.respond(to: requestOne)
        XCTAssertEqual(responseOne.body.bytes?.makeString(), "1")

        let requestTwo = Request(method: .get, path: "foo/slug-val/two")
        let responseTwo = try router.respond(to: requestTwo)
        XCTAssertEqual(responseTwo.body.bytes?.makeString(), "2")    }

    func testRouteLogs() throws {
        let router = Router()
        let responder = Request.Handler { _ in return Response() }
        router.register(path: ["foo", "bar", ":id"], responder: responder)
        router.register(path: ["foo", "bar", ":id", "zee"], responder: responder)
        router.register(path: ["1/2/3/4/5/6/7"], responder: responder)
        router.register(method: .post, path: ["multi-path"], responder: responder)
        router.register(method: .put, path: ["multi-path"], responder: responder)

        let expectation = [
            "* POST multi-path",
            "* PUT multi-path",
            "* GET 1/2/3/4/5/6/7",
            "* GET foo/bar/:id",
            "* GET foo/bar/:id/zee"
        ]

        XCTAssertEqual(Set(router.routes), Set(expectation))
    }

    func testRouterThrows() {
        let router = Router()

        do {
            let request = Request(method: .get, path: "asfd")
            _ = try router.respond(to: request)
            XCTFail("Should throw missing route")
        } catch {
            print(error)
        }
    }
}
