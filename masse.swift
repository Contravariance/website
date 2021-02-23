#!/usr/bin/swift

/// MASSE
/// Most Awful Static Site Engine
/// 
/// This is a single-file pure-swift static site engine
/// specifically built for the `Contravariance` podcast.
/// It was built on two train rides and offers a lot of
/// opportunities for improvements.

extension String {
    func between(beginString: String, endString: String) -> String? {
        // why is it still such a pain to grab a range out of string in swift...
        // I know I could use `NSRange` and then convert it, but that feels like cheating
        guard self.starts(with: beginString) && self.suffix(endString.count) == endString else {
            return nil
        }
        let beginPosition = self.index(self.startIndex, offsetBy: beginString.count).encodedOffset
        let endPosition = self.index(self.endIndex, offsetBy: -endString.count).encodedOffset
        return between(beginPosition: beginPosition, endPosition: endPosition)
    }

    func between(beginPosition: Int, endPosition: Int) -> String {
        let beginIndex = self.index(self.startIndex, offsetBy: beginPosition)
        let endIndex = self.index(self.startIndex, offsetBy: endPosition)
        return String(self[beginIndex..<endIndex])
    }
}

@_exported import Foundation

struct Masse {
    static func run() {
        let args = arguments(for: ProcessInfo.processInfo.arguments)
        guard args.count == 1 else {
            syntax()
        }
        let path = args.first.expect("Expecting config file path")
        let configurationURL = URL(fileURLWithPath: path)
        do {
            let configuration = try Configuration(path: configurationURL)
            var site = Site(configuration: configuration)
            try site.build()
        } catch let err {
            failedExecution("\(err)")
        }
    }
}

enum Keys {
    enum Configuration: String, CaseIterable {
    case templateFolder, podcastEntriesFolder, podcastTargetFolder, podcastTitle, entriesTemplate, podcastLink, podcastDescription, podcastKeywords, iTunesOwner, iTunesEmail, linkiTunes, linkOvercast, linkTwitter, linkPocketCasts, podcastAuthor, mp3FilesFolder

    }
    enum PodcastEntry: String, CaseIterable {
        case nr, title, date, file, duration, length, author, description, notes, guests
    }
}

extension Optional {
    func expect(_ error: String) -> Wrapped {
        guard let contents = self else {
            failedExecution(error)
        }
        return contents
    }
}

/// Replaces sections and variables within a template
/// sections are lines with the following syntax
/// ```
/// {{SECTION name="meta"}}
/// ```
/// variables are parts of a line with the following syntax:
/// ```
/// His name is #{name}#, he is #{age}# years old
/// ```
/// Loops look like this:
/// ```
/// {{LOOP from="posts" to="post" limit="0"}}
/// <h1>#{post.name} #{index}</h1>
/// {{ENDLOOP}}
/// ```
struct TemplateVariablesParser {
    private let variableStart = "#{"
    private let variableEnd = "}#"
    private let sectionStart = "{{SECTION name=\""
    private let sectionEnd = "\"}}"
    private let beginLoopStart = "{{LOOP "
    private let beginLoopEnd = "}}"
    private let endLoop = "{{ENDLOOP}}"
    private let sectionMap: [String: String]
    private let variablesMap: [String: String]
    private let contextMap: [String: [[String: String]]]
    private let contents: String
    
    struct Loop {
        let from: String
        let to: String
        let limit: Int
        var contents: String
    }
    
    init(contents: String, sections: [String: String], variables: [String: String], context: [String: [[String: String]]]) {
        self.sectionMap = sections
        self.variablesMap = variables
        self.contents = contents
        self.contextMap = context
    }
    
    func retrieve() -> String {
        return parse(contents, variables: variablesMap).joined(separator: "\n")
    }
    
    private func parse(_ section: String, variables: [String: String]) -> [String] {
        var lines: [String] = []
        var currentLoop: Loop?
        for line in section.components(separatedBy: .newlines) {
            if let loop = currentLoop, line == endLoop {
                lines.append(contentsOf: applyLoop(loop))
                currentLoop = nil
            } else if currentLoop != nil {
                currentLoop?.contents.append("\(line)\n")
            } else if let beginLoop = isLoopLine(line: line) {
                currentLoop = beginLoop
            } else {
                lines.append(lineWithVariablesSubstituted(line: lineOrSectionReplacement(line: line, variables: variables), variables: variables))
            }
        }
        return lines
    }
    
    private func applyLoop(_ loop: Loop) -> [String] {
        guard let items = contextMap[loop.from] else {
            log("No context for loop with \(loop.from)")
            return []
        }
        var lines: [String] = []
        let amount = loop.limit > 0 ? loop.limit : items.count
        for idx in 0..<min(amount, items.count) {
            var variables = variablesMap
            variables["index"] = String(idx + 1)
            for (key, value) in items[idx] {
                variables["\(loop.to).\(key)"] = value
            }
            lines.append(contentsOf: parse(loop.contents, variables: variables))
        }
        return lines
    }
    
    private func isLoopLine(line: String) -> Loop? {
        guard let (inner, _, _) = nameBetweenIdentifiers(line: line, begin: beginLoopStart, end: beginLoopEnd) else {
            return nil
        }
        let keyValueSequence = inner.components(separatedBy: .whitespaces)
            .map({ $0.replacingOccurrences(of: "\"", with: "").split(separator: "=") })
            .map { ($0[0], $0[1]) }
        let dict: [Substring: Substring] = Dictionary(uniqueKeysWithValues: keyValueSequence)
        guard let fromValue = dict["from"], let toValue = dict["to"] else {
            log("Not enough parameters for loop dictionary in: \(dict)")
            return nil
        }
        let limitValue = (dict["limit"].map { Int($0) ?? 0 }) ?? 0
        return Loop(from: String(fromValue), to: String(toValue), limit: limitValue, contents: "")
    }
    
    private func lineWithVariablesSubstituted(line: String, variables: [String: String]) -> String {
        var internalLine = line
        while true {
            guard let (name, start, end) = nameBetweenIdentifiers(line: internalLine, begin: variableStart, end: variableEnd) else {
                break
            }
            let variable = variables[name]

            /// if the variable name is `guests` and the content is empty, return an empty line. hack
            if variable == nil && name == "entry.guests" {
                return ""
            }
            guard let actualVariable = variables[name] else {
                log("Unknown variable \(name)")
                break
            }
            internalLine.replaceSubrange(start..<end, with: actualVariable)
        }
        return internalLine
    }
    
    private func lineOrSectionReplacement(line: String, variables: [String: String]) -> String {
        guard let (name, _, _) = nameBetweenIdentifiers(line: line, begin: sectionStart, end: sectionEnd) else {
            return line
        }
        guard let section = sectionMap[name] else {
            log("Unknown section: \(name)")
            return ""
        }
        // there may be variables in the section
        return parse(section, variables: variables).joined(separator: "\n")
    }
    
    private func nameBetweenIdentifiers(line: String, begin: String, end: String) -> (String, String.Index, String.Index)? {
        guard let startRange = line.range(of: begin),
            let endRange = line.range(of: end) else {
                return nil
        }
        return (String(line[startRange.upperBound..<endRange.lowerBound]), startRange.lowerBound, endRange.upperBound)
    }
}

func syntax() -> Never {
    print("Syntax:")
    print("masse [path to configuration file].bacf")
    exit(0)
}

func failedExecution(_ error: String) -> Never {
    print("Execution Failed with Error:")
    print("'\(error)'")
    exit(1)
}

func log(_ message: String) {
    print(message)
}

/// Detect blocks within the template file.
/// Blocks have the following syntax:
/// ```
/// <html>
/// {{BEGIN name="meta"}}
/// <meta name="#{name}#" content="#{value}#">
/// {{END}}
/// <body></body>
/// ```
/// I.e. {{BEGIN name="..."}} [something] {{END}}
///
/// Parsing is not recursive, i.e. blocks in blocks are not supported
struct TemplateBlockParser {
    private let beginMarkerStart = "{{BEGIN name=\""
    private let beginMarkerEnd = "\"}}"
    private let endMarkerStart = "{{END}}"
    private let contents: String
    
    private var currentName: String?
    private var currentLines: [String] = []
    
    private var cleanedContents: [String] = []
    private var sections: [String: String] = [:]
    
    init(contents: String) {
        self.contents = contents
        parse()
    }
    
    func retrieve() -> (String, [String: String]) {
        return (cleanedContents.joined(separator: "\n"), sections)
    }
    
    private mutating func parse() {
        for line in contents.components(separatedBy: .newlines) {
            if let name = line.between(beginString: beginMarkerStart, endString: beginMarkerEnd) {
                currentName = name
            } else if line.starts(with: endMarkerStart) {
                takeSection()
            } else if currentName != nil {
                currentLines.append(line)
                cleanedContents.append(line)
            } else {
                cleanedContents.append(line)
            }
        }
    }

    private mutating func takeSection() {
        guard let name = currentName else { return }
        sections[name] = currentLines.joined(separator: "\n")
        currentName = nil
        currentLines.removeAll()
    }
}

func arguments(for originalArguments: [String]) -> [String] {
    // Main Entry Point
    // calling swift on the commandline inserts a lot of additional arguments.
    // we're only interested in everything behind the --
    // If we have a '--' then we're in script mode, otherwise we're in executable mode
    // then all arguments count
    if let idx = originalArguments.firstIndex(where: { $0 == "--" }) {
        return Array(originalArguments[(idx + 1)..<originalArguments.endIndex])
    } else {
        return originalArguments
    }
}

struct Template {
    let path: URL
    let contents: String
    let cleanedContents: String
    let sections: [String: String]
    
    init(path: URL) throws {
        self.path = path
        self.contents = try String(contentsOf: path)
        let parser = TemplateBlockParser(contents: self.contents)
        (self.cleanedContents, self.sections) = parser.retrieve()
    }
    
    func renderOut(variables: [String: String], sections: [String: String], context: [String: [[String: String]]], to file: URL? = nil) throws {
        let parser = TemplateVariablesParser(contents: cleanedContents, sections: sections, variables: variables, context: context)
        let rendered = parser.retrieve()
        let finalOutFile = file ?? outfile()
        log("Writing \(path) to \(finalOutFile)")
        try rendered.write(to: finalOutFile, atomically: true, encoding: .utf8)
    }
    
    private func outfile() -> URL {
        // the first char of the filename is a _
        let filename = path.lastPathComponent.dropFirst()
        return path.deletingLastPathComponent().appendingPathComponent(String(filename))
    }
}

struct ConfigEntryParser {
    private let metaPrefix = "- "
    private let metaSeperator = ": "
    private let seperator = "---"
    private let contents: String
    private let keys: [String]
    private let overflowKey: String?
    
    init(contents: String, keys: [String], overflowKey: String? = nil) {
        self.contents = contents
        self.keys = keys
        self.overflowKey = overflowKey
    }
    
    init(url: URL, keys: [String], overflowKey: String? = nil) throws {
        let contents = try String(contentsOf: url)
        self.init(contents: contents, keys: keys, overflowKey: overflowKey)
    }
    
    func retrieve() -> [String: String] {
        var hasReachedSeperator = false
        var result: [String: String] = [:]
        var notesLines = ""
        for line in contents.components(separatedBy: .newlines) {
            if hasReachedSeperator {
                notesLines.append("\(line)\n")
            } else {
                for key in keys {
                    let start = "\(metaPrefix)\(key)\(metaSeperator)"
                    if line.starts(with: start),
                        let range = line.range(of: metaSeperator) {
                        result[key] = String(line[range.upperBound..<line.endIndex])
                    }
                }
                if line == seperator && overflowKey != nil {
                    hasReachedSeperator = true
                }
            }
        }
        overflowKey.map { result[$0] = notesLines }
        return result
    }
}

/// Read MP3 files and parse the headers in order to calculate the duration of the
/// MP3 file.
/// Supports constant bitrate and variable bitrate
/// Links:
/// - [Format reference](https://www.codeproject.com/Articles/8295/MPEG-Audio-Frame-Header)
/// - [Audio test file source](http://freemusicarchive.org/music/Karine_Gilanyan/Beethovens_Sonata_No_15_in_D_Major/Beethoven_-_Piano_Sonata_nr15_in_D_major_op28_Pastoral_-_I_Allegro)
/// - [Non-audio test file source](https://www.pexels.com/photo/close-up-of-tiled-floor-258805/)


/// Errors that can happen during reading the input stream
enum InputStreamError: Error {
    case endOfBuffer
    case streamError(Error?)
}

extension InputStream {
    /// Read `length` into a buffer. Throw an `InputStreamError` on failure
    func readInto(buffer: UnsafeMutablePointer<UInt8>, length: Int) throws {
        switch self.read(buffer, maxLength: length) {
        case 0: throw InputStreamError.endOfBuffer
        case -1: throw InputStreamError.streamError(self.streamError)
        default: ()
        }
    }
}

/// Various errors that can happen during MP3 decoding
/// Especially for invalid MP3 files
enum MP3DurationError: Error {
    case streamNotOpen
    case invalidFile(URL)
    case forbiddenVersion(UInt32)
    case forbiddenLayer
    case forbiddenMode
    case invalidBitrate(Int)
    case invalidSamplingRate(Int)
    case unexpectedFrame(Int)
    case readError(Error)
}

/// Lightweight wrapper around the seconds and nanoseconds
/// that are encoded in an MP3 file
public struct Duration {
    public private(set) var seconds: Double
    
    public var minutes: Double {
        return seconds / 60.0
    }
    
    init() {
        seconds = 0
    }
    
    init(seconds: UInt64, nanoseconds: UInt64) {
        self.seconds = Double(seconds)
        self.add(nanoseconds: nanoseconds)
    }
    
    mutating func add(seconds: UInt64) {
        self.seconds += Double(seconds)
    }
    
    mutating func add(nanoseconds: UInt64) {
        let nanosPerSec = 1_000_000_000
        self.seconds += Double(nanoseconds) / Double(nanosPerSec)
    }
}

extension Duration: CustomStringConvertible {
    public var description: String {
        // NSDateComponentsFormatter could also be used
        let minutes: Double = seconds / 60.0
        let remainingSeconds = seconds.truncatingRemainder(dividingBy: 60.0)
        let hours: Double = minutes / 60.0
        let remainingMinutes = minutes.truncatingRemainder(dividingBy: 60.0)
        return String(format: "%02d:%02d:%02d", Int(hours), Int(remainingMinutes), Int(remainingSeconds))
    }
}

/// Calculate the duration of an MP3 file
/// Can be initialized with a `URL` or a `NSInputStream`. Note that the inputStream has to be opened!
/// https://www.mp3-tech.org/programmer/frame_header.html
public struct MP3DurationCalculator {
    
    private let inputStream: InputStream
    
    /// Constants
    /// Various constants for MP3 Decoding
    
    private enum Version: Int {
        case mpeg1, mpeg2, mpeg25
        
        static func fromHeader(_ header: UInt32) throws -> Version {
            // Shift by 19 to reach the two bits at position 19, 20
            // then and with 0b11000000 so that only position 19/20 stay
            // and then convert them (00, 01, 10, 11) to a number
            // its is the same for the code below
            let number = (header >> 19) & 0b11

            switch number {
            case 0: return .mpeg25
            case 2: return .mpeg2
            case 3: return .mpeg1
            default: throw MP3DurationError.forbiddenVersion(number)
            }
        }
    }
    
    private enum Layer: Int {
        case notDefined, layer1, layer2, layer3
        
        static func fromHeader(_ header: UInt32) throws -> Layer {
            let number = (header >> 17) & 0b11
            switch number {
            case 0: return .notDefined
            case 1: return .layer3
            case 2: return .layer2
            case 3: return .layer1
            default: throw MP3DurationError.forbiddenLayer
            }
        }
    }
    
    private enum Mode: Int {
        case stereo, jointStereo, dualChannel, mono
        
        static func fromHeader(_ header: UInt32) throws -> Mode {
            let number = (header >> 6) & 0b11
            switch number {
            case 0: return .stereo
            case 1: return .jointStereo
            case 2: return .dualChannel
            case 3: return .mono
            default: throw MP3DurationError.forbiddenMode
            }
        }
    }
    
    private let bitRates = [
        [
            Array(repeating: 0, count: 16),
            // Mpeg1 Layer1
            [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0],
            // Mpeg1 Layer2
            [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0],
            // Mpeg1 Layer3
            [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
            ],
        [
            Array(repeating: 0, count: 16),
            // Mpeg2 Layer1
            [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0],
            // Mpeg2 Layer2
            [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
            // Mpeg2 Layer3
            [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
            ],
        [
            Array(repeating: 0, count: 16),
            // Mpeg25 Layer1
            [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0],
            // Mpeg25 Layer2
            [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
            // Mpeg25 Layer3
            [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
            ],
        ]
    
    private let samplingRates = [
        [44100, 48000, 32000, 0], // Mpeg1
        [22050, 24000, 16000, 0], // Mpeg2
        [11025, 12000, 8000, 0], // Mpeg25
    ]
    
    private let samplesPerFrame = [
        [0, 384, 1152, 1152], // Mpeg1
        [0, 384, 1152, 576],  // Mpeg2
        [0, 384, 1152, 576], // Mpeg25
    ]
    
    private let sideInformationSizes = [
        [32, 32, 32, 17], // Mpeg1
        [17, 17, 17, 9],  // Mpeg2
        [17, 17, 17, 9], // Mpeg25
    ]
    
    private func calculateBitrate(for version: Version, layer: Layer, encodedBitrate: Int) throws -> Int {
        guard encodedBitrate < 15 else {
            throw MP3DurationError.invalidBitrate(encodedBitrate)
        }
        guard layer != .notDefined else {
            throw MP3DurationError.forbiddenLayer
        }
        return 1000 * bitRates[version.rawValue][layer.rawValue][encodedBitrate]
    }
    
    private func calculateSamplingRate(for version: Version, encodedSamplingRate: Int) throws -> Int {
        guard encodedSamplingRate < 3 else {
            throw MP3DurationError.invalidSamplingRate(encodedSamplingRate)
        }
        return samplingRates[version.rawValue][encodedSamplingRate]
    }
    
    private func calculateSamplesPerFrame(for version: Version, layer: Layer) throws -> Int {
        guard layer != .notDefined else {
            throw MP3DurationError.forbiddenLayer
        }
        return samplesPerFrame[version.rawValue][layer.rawValue]
    }
    
    private func calculateSideInformationSize(for version: Version, mode: Mode) throws -> Int {
        return sideInformationSizes[version.rawValue][mode.rawValue]
    }
    
    /// Lightweight wrapper around a `UnsafeMutablePointer` in order to read unneeded
    /// data from a inputStream into something. This will resize the buffer according
    /// to the size requirements.
    private struct Dump {
        private var buffer: UnsafeMutablePointer<UInt8>
        private var size = 16 * 1024
        
        init() {
            self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.size)
        }
        
        mutating func skip(reader: InputStream, length: Int) throws {
            if length > size {
                buffer.deallocate()
                buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
                self.size = length
            }
            try reader.readInto(buffer: self.buffer, length: length)
        }
    }
    
    /// Initialize the Calculator with a `URL` to an mp3 file
    public init(url: URL) throws {
        guard let inputStream = InputStream(url: url) else {
            throw MP3DurationError.invalidFile(url)
        }
        inputStream.open()
        try self.init(inputStream: inputStream)
    }
    
    /// Initialize the Calculator with an `openend` `NSInputStream`. This is particularly
    /// useful as `NSInputStream`s can also be contructed from `NSData`
    /// throws if the stream is not open
    public init(inputStream: InputStream) throws {
        guard inputStream.streamStatus == .open else {
            throw MP3DurationError.streamNotOpen
        }
        self.inputStream = inputStream
    }
    
    /// Calculate the duration of an MP3 file by parsing headers
    public func calculateDuration() throws -> Duration {
        defer {
            inputStream.close()
        }
        let headerBufferLength = 4
        let headerBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: headerBufferLength)
        headerBuffer.initialize(repeating: 0, count: headerBufferLength)
        
        var dump = Dump()
        
        var duration = Duration()
        while true {
            do {
                try inputStream.readInto(buffer: headerBuffer, length: headerBufferLength)
            } catch InputStreamError.endOfBuffer {
                break
            } catch let error {
                throw MP3DurationError.readError(error)
            }
            let header = (UInt32(headerBuffer.pointee)) << 24
                | (UInt32(headerBuffer.advanced(by: 1).pointee)) << 16
                | (UInt32(headerBuffer.advanced(by: 2).pointee)) << 8
                | (UInt32(headerBuffer.advanced(by: 3).pointee))
            
            let isMP3 = (header >> 21) == 0x7ff
            if isMP3 {
                let version = try Version.fromHeader(header)
                let layer = try Layer.fromHeader(header)
                let mode = try Mode.fromHeader(header)
                let encodedBitrate = (header >> 12) & 0b1111
                let encodedSamplingRate = (header >> 10) & 0b11
                let padding = ((header >> 9) & 1) != 0 ? 1 : 0
                let samplingRate = try calculateSamplingRate(for: version, encodedSamplingRate: Int(encodedSamplingRate))
                let numSamples = try calculateSamplesPerFrame(for: version, layer: layer)
                let xingOffset = try calculateSideInformationSize(for: version, mode: mode)
                
                let xingBufferLength = 12
                let xingBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: xingBufferLength)
                xingBuffer.initialize(repeating: 0, count: xingBufferLength)
                
                try dump.skip(reader: inputStream, length: xingOffset)
                
                try inputStream.readInto(buffer: xingBuffer, length: xingBufferLength)
                let tag = String(bytesNoCopy: xingBuffer, length: 4, encoding: .ascii, freeWhenDone: false)
                
                let billion: UInt64 = 1_000_000_000
                
                if tag == "Xing" || tag == "Info" {
                    let hasFrames = (xingBuffer.advanced(by: 7).pointee & 1) != 0
                    if hasFrames {
                        let numFrames = (UInt32(xingBuffer.advanced(by: 8).pointee)) << 24
                            | (UInt32(xingBuffer.advanced(by: 9).pointee)) << 16
                            | (UInt32(xingBuffer.advanced(by: 10).pointee)) << 8
                            | (UInt32(xingBuffer.advanced(by: 11).pointee))
                        let rate = UInt64(samplingRate)
                        let framesBySamples = UInt64(numFrames) * UInt64(numSamples)
                        let seconds = framesBySamples / rate
                        let nanoseconds = (billion * framesBySamples) / rate - billion * seconds
                        return Duration(seconds: seconds, nanoseconds: nanoseconds)
                    }
                }
                
                let bitrate = try calculateBitrate(for: version, layer: layer, encodedBitrate: Int(encodedBitrate))
                let frameLength = (numSamples / 8 * bitrate / samplingRate + padding)
                
                try dump.skip(reader: inputStream, length: frameLength - headerBufferLength - xingOffset - xingBufferLength)
                
                let frameDuration = (UInt64(numSamples) * billion) / UInt64(samplingRate)
                duration.add(nanoseconds: frameDuration)
                continue
            }
            
            // ID3v2 frame
            let isID3v2 = "ID3" == String(bytesNoCopy: headerBuffer, length: 3, encoding: .ascii, freeWhenDone: false)
            if isID3v2 {
                let id3v2Length = 6
                let id3v2Buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: id3v2Length)
                id3v2Buffer.initialize(repeating: 0, count: id3v2Length)
                try inputStream.readInto(buffer: id3v2Buffer, length: id3v2Length)
                let flags = id3v2Buffer.advanced(by: 1).pointee
                let footerSize = (flags & 0b0001_0000) != 0 ? 10 : 0
                let tagSize = Int(UInt32(id3v2Buffer.advanced(by: 5).pointee)
                    | (UInt32(id3v2Buffer.advanced(by: 4).pointee) << 7)
                    | (UInt32(id3v2Buffer.advanced(by: 3).pointee) << 14)
                    | (UInt32(id3v2Buffer.advanced(by: 2).pointee) << 21))
                
                
                try dump.skip(reader: inputStream, length: tagSize + footerSize)
                continue
            }
            
            // ID3v1 frame
            let isID3v1 = "TAG" == String(bytesNoCopy: headerBuffer, length: 3, encoding: .ascii, freeWhenDone: false)
            if isID3v1 {
                try dump.skip(reader: inputStream, length: 128 - headerBufferLength)
                continue
            }
            
            throw MP3DurationError.unexpectedFrame(Int(header))
        }
        
        return duration
    }
}

/// Takes a site configuration and generates
struct Site {
    private let configuration: Configuration
    private var context: [String: [[String: String]]] = [:]
    private var sections: [String: String] = [:]
    private var variables: [String: String] = [:]
    private var entries: [PodcastEntry] = []
    private var templates: [Template] = []
    private var entriesTemplate: Template?
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    mutating func build() throws {
        try parseEntries()
        try parseTemplates()
        makeRenderState()
        try renderPages()
        try renderEntries()
    }
    
    /// Goes through all the posts
    private mutating func parseEntries() throws {
        var guests = [[String: String]]()
        for file in try FileManager.default.contentsOfDirectory(atPath: configuration.podcastEntriesFolder) {
            let url = URL(fileURLWithPath: "\(configuration.podcastEntriesFolder)/\(file)")
            guard url.pathExtension == "bacf" else { continue }
            let parsed = try ConfigEntryParser(url: url, keys: Keys.PodcastEntry.allCases.map { $0.rawValue }, overflowKey: Keys.PodcastEntry.notes.rawValue)
            let entry = PodcastEntry(meta: parsed.retrieve(), filename: file, folder: configuration.mp3FilesFolder)
            entries.append(entry)

            for guest in entry.guests {
                let guestEntry = ["name": guest, "episode": (entry.meta["nr"] ?? "Anon")]
                guests.append(guestEntry)
            }
        }
        let sortedGuests: [[String: String]] = guests.sorted(by: { (a, b) in
          guard let first = a["name"], let second = b["name"]  else { return false }
          return first.trimmingCharacters(in: .whitespaces).lowercased() < second.trimmingCharacters(in: .whitespaces).lowercased()
        })

        self.context["guests"] = sortedGuests
    }
    
    /// Goes through all .html files beginning with a _ and collect their sections.
    /// then, write them all into non _ files
    private mutating func parseTemplates() throws {
        for file in try FileManager.default.contentsOfDirectory(atPath: configuration.templateFolder) {
            guard file.starts(with: "_") else { continue }
            let path = "\(configuration.templateFolder)/\(file)"
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue == false else { continue }
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension == "html" || url.pathExtension == "rss" else { continue }
            let template = try Template(path: url)
            if file == configuration.entriesTemplate {
                entriesTemplate = template
            } else {
                templates.append(template)
            }
        }
    }
    
    private mutating func makeRenderState() {
        for page in templates {
            sections.merge(page.sections) { a, _ -> String in
                failedExecution("Duplicate section named \(a) in \(page.path)")
            }
        }
        context["entries"] = entries.sorted(by: { post1, post2 -> Bool in
            return post1.date > post2.date
        }).map { $0.meta }
        variables.merge(configuration.meta) { a, _ -> String in
            failedExecution("Duplicate variables key \(a)")
        }
        variables["buildDate"] = PodcastEntry.podcastDateFormatter.string(from: Date())
    }
    
    private func renderPages() throws {
        for page in templates {
            try page.renderOut(variables: variables, sections: sections, context: context)
        }
    }
    
    private func renderEntries() throws {
        let template = entriesTemplate.expect("Entries Template file \(configuration.entriesTemplate) not found")
        for entry in entries {
            var customVariables = variables
            customVariables.merge(entry.meta) { a, _ -> String in
                failedExecution("variables key \(a) also exists in entry \(entry.filename)")
            }
            let outFile = URL(fileURLWithPath: configuration.podcastTargetFolder)
                .appendingPathComponent(entry.filename)
                .deletingPathExtension()
                .appendingPathExtension("html")
            log("Writing \(entry.filename) to \(outFile)")
            try template.renderOut(variables: customVariables, sections: sections, context: context, to: outFile)
        }
    }
}

struct PodcastEntry {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    static let podcastDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Wed, 08 Aug 2018 19:00:00 GMT
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd LLL yyyy HH:mm:ss z"
        return formatter
    }()
    
    var meta: [String: String]
    let date: Date
    var guests: [String] = []
    let filename: String
    
    init(meta: [String: String], filename: String, folder: String) {
        self.meta = meta
        self.filename = filename
        let dateString = meta[Keys.PodcastEntry.date.rawValue].expect("Need \(Keys.PodcastEntry.date.rawValue) entry in podcast entry \(filename)")
        date = PodcastEntry.dateFormatter.date(from: dateString).expect("Invalid formatted date \(dateString) in post \(filename)")
        
        // insert the podcast-format date into the meta
        self.meta["podcastDate"] = PodcastEntry.podcastDateFormatter.string(from: date)
        
        // calculate the duration
        guard let mp3Filename = meta[Keys.PodcastEntry.file.rawValue] else {
            return
        }
        let url = URL(fileURLWithPath: "\(folder)/\(mp3Filename)")
        guard let data = try? Data(contentsOf: url) else {
            print("Could not read mp3 file `\(url)`")
            return
        }
        self.guests = self.meta[Keys.PodcastEntry.guests.rawValue]?.split(separator: ",").map(String.init) ?? []

        self.meta[Keys.PodcastEntry.length.rawValue] = "\(data.count)"
        let stream = InputStream(data: data)
        do {
            stream.open()
            let calculator = try MP3DurationCalculator(inputStream: stream)
            let duration = try calculator.calculateDuration()
            self.meta[Keys.PodcastEntry.duration.rawValue] = duration.description
        } catch let error {
            print("Could not caculate duration of MP3: \(mp3Filename)\n\t\(error)")
        }
    }
}

struct Configuration {
    /// The folder that houses the _ templates
    var templateFolder = ""
    /// The folder where all the posts are
    var podcastEntriesFolder = ""
    /// The folder where the posts are written to
    var podcastTargetFolder = ""
    /// The title of the podcast
    var podcastTitle = ""
    /// The template to use for each entry
    var entriesTemplate = ""
    /// The folder where the mp3 files are
    var mp3FilesFolder = ""
    /// The remaining meta
    var meta: [String: String] = [:]
    
    init(path: URL) throws {
        let parsed = try ConfigEntryParser(url: path, keys: Keys.Configuration.allCases.map { $0.rawValue }).retrieve()
        let entries: [(WritableKeyPath<Configuration, String>, Keys.Configuration)] = [
            (\Configuration.templateFolder, .templateFolder),
            (\Configuration.podcastEntriesFolder, .podcastEntriesFolder),
            (\Configuration.podcastTargetFolder, .podcastTargetFolder),
            (\Configuration.podcastTitle, .podcastTitle),
            (\Configuration.mp3FilesFolder, .mp3FilesFolder),
            (\Configuration.entriesTemplate, .entriesTemplate)]
        for (keyPath, key) in entries {
            self[keyPath: keyPath] = parsed[key.rawValue].expect("Need \(key.rawValue) entry in configuration")
        }
        meta = parsed
    }
}


Masse.run()
