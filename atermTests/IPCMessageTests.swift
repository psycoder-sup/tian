import Testing
import Foundation
@testable import aterm

struct IPCMessageTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - IPCValue round-trip

    @Test func valueString() throws {
        let value = IPCValue.string("hello")
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.stringValue == "hello")
    }

    @Test func valueInt() throws {
        let value = IPCValue.int(42)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.intValue == 42)
    }

    @Test func valueBool() throws {
        let value = IPCValue.bool(true)
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(IPCValue.self, from: data)
        #expect(decoded == value)
        #expect(decoded.boolValue == true)
    }

    @Test func valueNull() throws {
        let value = IPCValue.null
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(IPCValue.self, from: data)
        #expect(decoded == value)
    }

    @Test func valueArray() throws {
        let value = IPCValue.array([.string("a"), .int(1), .bool(false)])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(IPCValue.self, from: data)
        #expect(decoded == value)
    }

    @Test func valueNestedObject() throws {
        let value = IPCValue.object([
            "name": .string("test"),
            "count": .int(3),
            "items": .array([.string("x"), .string("y")]),
        ])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(IPCValue.self, from: data)
        #expect(decoded == value)
    }

    @Test func valueAccessorsReturnNilForWrongType() {
        let value = IPCValue.string("hello")
        #expect(value.intValue == nil)
        #expect(value.boolValue == nil)

        let intVal = IPCValue.int(5)
        #expect(intVal.stringValue == nil)
        #expect(intVal.boolValue == nil)
    }

    // MARK: - IPCRequest round-trip

    @Test func requestRoundTrip() throws {
        let request = IPCRequest(
            version: 1,
            command: "workspace.create",
            params: ["name": .string("my-project"), "directory": .string("/tmp/test")],
            env: IPCEnv(
                paneId: "aaa-bbb",
                tabId: "ccc-ddd",
                spaceId: "eee-fff",
                workspaceId: "ggg-hhh"
            )
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(IPCRequest.self, from: data)
        #expect(decoded.version == 1)
        #expect(decoded.command == "workspace.create")
        #expect(decoded.params["name"]?.stringValue == "my-project")
        #expect(decoded.params["directory"]?.stringValue == "/tmp/test")
        #expect(decoded.env.paneId == "aaa-bbb")
        #expect(decoded.env.workspaceId == "ggg-hhh")
    }

    @Test func requestWithEmptyParams() throws {
        let request = IPCRequest(
            version: 1,
            command: "ping",
            params: [:],
            env: IPCEnv(paneId: "", tabId: "", spaceId: "", workspaceId: "")
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(IPCRequest.self, from: data)
        #expect(decoded.command == "ping")
        #expect(decoded.params.isEmpty)
    }

    // MARK: - IPCResponse round-trip

    @Test func successResponse() throws {
        let response = IPCResponse.success(["id": .string("uuid-123")])
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(IPCResponse.self, from: data)
        #expect(decoded.ok == true)
        #expect(decoded.result?["id"]?.stringValue == "uuid-123")
        #expect(decoded.error == nil)
    }

    @Test func failureResponse() throws {
        let response = IPCResponse.failure(code: 1, message: "Not found")
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(IPCResponse.self, from: data)
        #expect(decoded.ok == false)
        #expect(decoded.result == nil)
        #expect(decoded.error?.code == 1)
        #expect(decoded.error?.message == "Not found")
    }

    @Test func emptySuccessResponse() throws {
        let response = IPCResponse.success()
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(IPCResponse.self, from: data)
        #expect(decoded.ok == true)
        #expect(decoded.result?.isEmpty == true)
    }

    // MARK: - Protocol version

    @Test func protocolVersionIsOne() {
        #expect(ipcProtocolVersion == 1)
    }
}
