// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import Foundation
import ArgumentParser
@_spi(Support) import MachOKit

@main
struct inject_o: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inject-o",
        abstract: "Inject dependent dylibs into the Mach-O file",
        version: "0.1.0"
    )

    @Argument(help: "Path to the input Mach-O file.")
    var inputPath: String

    @Option(name: .shortAndLong, help: "Path to the dylib to be added")
    var dylib: String

    @Option(name: .shortAndLong, help: "Path to the output Mach-O file (default: <input>.injected)")
    var output: String?

    @Flag(name: .shortAndLong, help: "Add as LC_LOAD_WEAK_DYLIB")
    var `weak`: Bool = false

    @Flag(name: .shortAndLong, help: "Add as LC_LOAD_UPWARD_DYLIB")
    var upward: Bool = false

    @Flag(name: .long, help: "Suppress all output.")
    var quiet: Bool = false

    var isCreatedCopy: Bool = false

    var inputURL: URL { .init(fileURLWithPath: inputPath) }
    var outputURL: URL {
        if let output {
            URL(fileURLWithPath: output)
        } else {
            inputURL.appendingPathExtension("injected")
        }
    }

    var fileManager: FileManager { .default }

    mutating func run() throws {
        let machOFiles = try loadMachOFiles()
        for machO in machOFiles {
            try process(for: machO)
        }
        print("[INFO] Done")
    }
}

extension inject_o {
    func loadMachOFiles() throws -> [MachOFile] {
        let file = try MachOKit.loadFromFile(url: inputURL)
        return switch file {
        case .fat(let fat):
            try fat.machOFiles()
        case .machO(let machO):
            [machO]
        }
    }

    mutating func process(for machO: MachOFile) throws {
        print("[INFO] Processing for \(machO.imagePath) (\(machO.header.cpu))")

        print("[INFO] Existing dependencies:")
        let dependencies = machO.dependencies
        for dependency in dependencies {
            let dylib = dependency.dylib
            print(" - \(dylib.name) (\(dependency.type))")
        }

        if dependencies.map(\.dylib.name).contains(dylib) {
            fatalError("\"\(dylib)\" is already existed in dependencies")
        }

        print("[INFO] Preparing to add new load command:")
        print(" - Type: \(`weak` ? "LC_LOAD_WEAK_DYLIB" : upward ? "LC_LOAD_UPWARD_DYLIB" : "LC_LOAD_DYLIB")")
        print(" - Path: \(dylib)")

        let commandData = createNewDylibCommandData()

        guard try machO.canInsertLoadCommand(size: commandData.count) else {
            fatalError("There is not enough space to insert loadCommand")
        }

        if !isCreatedCopy {
            try copyBinaly()
            isCreatedCopy = true
        }

        try inject(command: commandData, to: machO)
    }
}

extension inject_o {
    func copyBinaly() throws {
        print("[INFO] Copy input binary for output")
        try fileManager.copyItem(at: inputURL, to: outputURL)
    }

    func createNewDylibCommandData() -> Data {
        let cmd = `weak` ? LC_LOAD_WEAK_DYLIB : upward ? LC_LOAD_UPWARD_DYLIB : UInt32(LC_LOAD_DYLIB)

        let stringData = dylib.data(using: .utf8)!
        let cmdsize = DylibCommand.layoutSize + stringData.count

        let dylib: dylib = .init(
            name: .init(offset: numericCast(DylibCommand.layoutSize)),
            timestamp: 0,
            current_version: 0,
            compatibility_version: 0
        )
        var layout: dylib_command = .init(
            cmd: cmd,
            cmdsize: numericCast(cmdsize),
            dylib: dylib
        )

        let padding = (8 - (cmdsize % 8))
        layout.cmdsize += numericCast(padding)

        return DylibCommand.data(of: layout) + stringData + Data(count: padding)
    }

    func stripCodeSignIfNeeded(
        for machO: MachOFile,
        writeHandle: FileHandle
    ) throws -> Bool {
        guard case let .codeSignature(codeSign) = Array(machO.loadCommands).last else {
            return false
        }
        let size: Int = numericCast(codeSign.cmdsize)
        let offset = machO.loadCommandsEndOffset - size

        let zero = Data(count: size)

        try writeHandle.seek(toOffset: numericCast(offset))
        writeHandle.write(zero)

        return true
    }

    func inject(command data: Data, to machO: MachOFile) throws {
        let writeHandle = try FileHandle(forWritingTo: outputURL)

        print("[INFO] Strip code signature")
        let isStripped = try stripCodeSignIfNeeded(for: machO, writeHandle: writeHandle)
        let strippedSize = isStripped ? MemoryLayout<linkedit_data_command>.size : 0

        print("[INFO] Update Mach-O header")
        var _header = machO.header.layout
        if isStripped {
            _header.sizeofcmds -= numericCast(strippedSize)
            _header.sizeofcmds += numericCast(data.count)
        } else {
            _header.ncmds += 1
            _header.sizeofcmds += numericCast(data.count)
        }

        let ncmdsOffset = machO.headerStartOffset + MachHeader.layoutOffset(of: \.ncmds)
        try writeHandle.seek(toOffset: numericCast(ncmdsOffset))
        writeHandle.write(withUnsafeBytes(of: _header.ncmds, { Data($0) }))

        let sizeofcmdsOffset = machO.headerStartOffset + MachHeader.layoutOffset(of: \.sizeofcmds)
        try writeHandle.seek(toOffset: numericCast(sizeofcmdsOffset))
        writeHandle.write(withUnsafeBytes(of: _header.sizeofcmds, { Data($0) }))

        print("[INFO] Insert new load command")
        var offset = machO.loadCommandsEndOffset
        if isStripped { offset -= strippedSize }
        try writeHandle.seek(toOffset: numericCast(offset))
        writeHandle.write(data)
    }
}

extension inject_o {
    func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        if quiet { return }
        Swift.print(items, separator: separator, terminator: terminator)
    }
}

extension MachOFile {
    var loadCommandsEndOffset: Int {
        headerStartOffset + headerSize + numericCast(header.sizeofcmds)
    }

    func canInsertLoadCommand(size: Int) throws -> Bool {
        let offset = loadCommandsEndOffset
        var size = size
        let fileHandle = try FileHandle(forReadingFrom: url)

        if case let .codeSignature(codeSign) = Array(loadCommands).last {
            size -= numericCast(codeSign.cmdsize)
        }

        let data = fileHandle.readData(offset: numericCast(offset), size: size)

        let reminder: Int = numericCast(header.sizeofcmds) % 64

        let space = 64 - reminder + MemoryLayout<linkedit_data_command>.size
        print("[INFO] Avilable Space: \(space) bytes (string: \(space - DylibCommand.layoutSize))")

        return data.allSatisfy({ $0 == 0 })
    }
}

extension LayoutWrapper {
    var data: Data {
        Self.data(of: layout)
    }

    static func data(of layout: Layout) -> Data {
        var layout = layout
        return withUnsafeBytes(of: &layout) { ptr in
            Data(bytes: ptr.baseAddress!, count: layoutSize)
        }
    }
}
