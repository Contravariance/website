#!/usr/bin/swift

/// MASSE
/// Most Awful Static Site Engine
/// 
/// This is a single-file pure-swift static site engine
/// specifically built for the `Contravariance` podcast.
/// It was built on two train rides and offers a lot of
/// opportunities for improvements.

import Foundation

enum Keys {
    enum Configuration: String, CaseIterable {
        case templateFolder, podcastEntriesFolder, podcastTargetFolder, podcastTitle, entriesTemplate, podcastLink, podcastDescription, podcastKeywords, iTunesOwner, iTunesEmail, linkiTunes, linkOvercast, linkTwitter, linkPocketCasts, podcastAuthor

    }
    enum PodcastEntry: String, CaseIterable {
        case nr, title, date, file, duration, length, author, description, notes
    }
}

extension Optional {
    func expect(_ error: String) -> Wrapped {
        guard let contents = self else {
            fatalError(error)
        }
        return contents
    }
}

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
            print("No context for loop with \(loop.from)")
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
            print("Not enough parameters for loop dictionary in: \(dict)")
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
            guard let variable = variables[name] else {
                print("Unknown variable \(name)")
                break
            }
            internalLine.replaceSubrange(start..<end, with: variable)
        }
        return internalLine
    }
    
    private func lineOrSectionReplacement(line: String, variables: [String: String]) -> String {
        guard let (name, _, _) = nameBetweenIdentifiers(line: line, begin: sectionStart, end: sectionEnd) else {
            return line
        }
        guard let section = sectionMap[name] else {
            print("Unknown section: \(name)")
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
        print("Writing \(path) to \(finalOutFile)")
        try rendered.write(to: finalOutFile, atomically: true, encoding: .utf8)
    }
    
    private func outfile() -> URL {
        // the first char of the filename is a _
        let filename = path.lastPathComponent.dropFirst()
        return path.deletingLastPathComponent().appendingPathComponent(String(filename))
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
        formatter.dateFormat = "EEE, dd LLL yyyy HH:mm:ss z"
        return formatter
    }()
    
    var meta: [String: String]
    let date: Date
    let filename: String
    
    init(meta: [String: String], filename: String) {
        self.meta = meta
        self.filename = filename
        let dateString = meta[Keys.PodcastEntry.date.rawValue].expect("Need \(Keys.PodcastEntry.date.rawValue) entry in podcast entry \(filename)")
        date = PodcastEntry.dateFormatter.date(from: dateString).expect("Invalid formatted date \(dateString) in post \(filename)")
        // insert the podcast-format date into the meta
        self.meta["podcastDate"] = PodcastEntry.podcastDateFormatter.string(from: date)
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
    /// The remaining meta
    var meta: [String: String] = [:]
    
    init(path: URL) throws {
        let parsed = try ConfigEntryParser(url: path, keys: Keys.Configuration.allCases.map { $0.rawValue }).retrieve()
        let entries: [(WritableKeyPath<Configuration, String>, Keys.Configuration)] = [
            (\Configuration.templateFolder, .templateFolder),
            (\Configuration.podcastEntriesFolder, .podcastEntriesFolder),
            (\Configuration.podcastTargetFolder, .podcastTargetFolder),
            (\Configuration.podcastTitle, .podcastTitle),
            (\Configuration.entriesTemplate, .entriesTemplate)]
        for (keyPath, key) in entries {
            self[keyPath: keyPath] = parsed[key.rawValue].expect("Need \(key.rawValue) entry in configuration")
        }
        meta = parsed
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
        for file in try FileManager.default.contentsOfDirectory(atPath: configuration.podcastEntriesFolder) {
            let url = URL(fileURLWithPath: "\(configuration.podcastEntriesFolder)/\(file)")
            guard url.pathExtension == "bacf" else { continue }
            let parsed = try ConfigEntryParser(url: url, keys: Keys.PodcastEntry.allCases.map { $0.rawValue }, overflowKey: Keys.PodcastEntry.notes.rawValue)
            let entry = PodcastEntry(meta: parsed.retrieve(), filename: file)
            entries.append(entry)
        }
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
                fatalError("Duplicate section named \(a) in \(page.path)")
            }
        }
        context["entries"] = entries.sorted(by: { post1, post2 -> Bool in
            return post1.date > post2.date
        }).map { $0.meta }
        variables.merge(configuration.meta) { a, _ -> String in
            fatalError("Duplicate variables key \(a)")
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
                fatalError("variables key \(a) also exists in entry \(entry.filename)")
            }
            let outFile = URL(fileURLWithPath: configuration.podcastTargetFolder)
                .appendingPathComponent(entry.filename)
                .deletingPathExtension()
                .appendingPathExtension("html")
            print("Writing \(entry.filename) to \(outFile)")
            try template.renderOut(variables: customVariables, sections: sections, context: context, to: outFile)
        }
    }
}

func syntax() -> Never {
    print("Syntax:")
    print("masse [path to configuration file].bacf")
    exit(0)
}

// Main Entry Point
// calling swift on the commandline inserts a lot of additional arguments.
// we're only interested in everything behind the --
let args = ProcessInfo.processInfo.arguments.drop(while: { $0 != "--" }).dropFirst()
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
    fatalError("\(err)")
}
