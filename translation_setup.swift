// translation_setup.swift created by Douglas Boberg on 5/4/23. PUBLIC DOMAIN SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.

// MARK: - SETUP

// base language code for your Xcode project
let base = "en"

// translation target language codes
var languages = ["de","es","fr","it","ja","ko","pt-BR","ru","zh-Hans"]



// MARK: - NOTES

// Adds new or missing translation keys from the source code into the Base language files

// Can be run from command line or from Xcode. If running from Xcode, edit schema to pass in command line arguments

// >  swift translation_setup.swift

// >  swift translation_setup.swift  /User/..etc../projectfolder/



// MARK: - SCRIPT

import Foundation

let argumentURL:URL = CommandLine.arguments.count >= 2 ? URL(filePath: CommandLine.arguments[1]) : URL(filePath:".")
print(" ")
print("Processing \(argumentURL.path)")
print(" ")

print(" ")
print("1. Run genstrings for .m and .swift sourcecode  (1 of 2)")
print(" ")
await processSourceCode(projectURL: argumentURL)
print(" ")

print(" ")
print("2. Process PLIST files from Settings and InAppSettings bundles  (2 of 2)")
print(" ")
await processPlistFiles(projectURL: argumentURL)
print(" ")

func processSourceCode(projectURL: URL) async {
	// `genstrings` creates a Localizable.strings in the *LOCAL* working folder with translation keys from all .m and .swift files
	if let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
		for case let url as URL in enumerator {
			if !url.path.contains("Pods/") && !url.path.contains(".framework/")
				&& (url.pathExtension == "m" || url.pathExtension == "swift")
			{
				await shell("genstrings -a \(url.path)")
			}
		}
	}
	// convert the genstrings output to UTF-8 (genstrings creates a UTF-16 file https://stackoverflow.com/a/69174370 )
	await shell("iconv -f utf-16 -t utf-8 Localizable.strings > Localizable_utf8.txt")

	
	// keep the keys of the existing base language, if it exists
	var baseStringsMap: [String: String] = [:]
	if let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
		for case let url as URL in enumerator {
			if url.lastPathComponent == "Localizable.strings" && url.path.contains("\(base).lproj/") && !url.path.contains("Pods/") && !url.path.contains(".framework/")
			{
				baseStringsMap = await readStringsMap(url)
				break
			}
		}
	}

	// add any new Keys from the local utf8 file to the base language keys; do not overwrite the base language's key
	let utf8StringsMap = await readStringsMap(URL(filePath: "Localizable_utf8.txt"))
	let baseKeys = baseStringsMap.keys
	for key in utf8StringsMap.keys {
		if !baseKeys.contains(key) {
			baseStringsMap[key] = utf8StringsMap[key]
		}
	}
	
	let addKeys = Array(Set(baseStringsMap.keys))
	
	await writeLanguageFiles(projectURL, filename: "Localizable.strings", addKeys:addKeys)

	// cleanup
	await shell("rm Localizable.strings")
	await shell("rm Localizable_utf8.txt")
}


func processPlistFiles(projectURL: URL) async {
	// Get all of the plist files in any bundle...
	let plistURLs = findBundlePlistPaths(projectURL)
	guard plistURLs.count > 0 else {
		print(" -> Skipping Plist processing because no Plist files were found")
		print(" ")
		exit(0)
	}
	print("- Found \(plistURLs.count) bundle plist files to process")
	print(" ")
	
	
	// Group by separate unique Bundles
	var bundleURLs = Set<URL>()
	for plistURL in plistURLs {
		bundleURLs.insert(plistURL.deletingLastPathComponent())
	}
	
	// process each Bundle separately
	for bundleURL in bundleURLs {
		// each bundle gets a unique Strings filename, using the Bundle folder's name
		let stringsFilename = bundleURL.lastPathComponent.replacingOccurrences(of: ".bundle", with: ".strings")
		print("- Process \(stringsFilename) for \(bundleURL.path)")
		
		// get the Plists under this bundle only, then read them all into the plistKeys array
		let plistURLs = findBundlePlistPaths(bundleURL)
		var plistKeys:[String] = []
		for plistURL in plistURLs {
			plistKeys.append(contentsOf:getTitlesFromPlist(plistURL))
		}
		plistKeys = Array(Set(plistKeys))

		await writeLanguageFiles(bundleURL, filename: stringsFilename, addKeys:plistKeys)
	}
}


func writeLanguageFiles(_ rootURL:URL, filename:String, addKeys:[String]) async {
	// include the base language too because this is not translating this is just writing files.
	let allLanguages:[String] = await languages + [base]
	for language in allLanguages {
		// touch the file to make sure it exists
		let stringsURL = rootURL.appending(path: "\(language).lproj").appending(path: filename)
		touchFile(stringsURL)
		
		// read the existing Strings file
		var stringsMap = await readStringsMap(stringsURL)
		let stringsKeys = stringsMap.keys
		for key in addKeys {
			// add any Keys that are not already in the existing Strings file
			if !stringsKeys.contains(key) {
				stringsMap[key] = key
			}
		}
		
		// write them out in order
		let sortedKeys = stringsMap.keys.sorted()
		if let fileHandle = try? FileHandle(forWritingTo: stringsURL) {
			// empty the current file
			try? fileHandle.truncate(atOffset: 0)
			for key in sortedKeys {
				if let value = stringsMap[key], let data = "\n\"\(key)\" = \"\(value)\";\n".data(using: String.Encoding.utf8) {
					fileHandle.write(data)
					// print("  + wrote    \(key)    to:    \(stringsURL.path)")
				}
			}
			fileHandle.closeFile()
			print("- Wrote \(sortedKeys.count) translatable keys to \(stringsURL.path)")
		}
		
		
		//	print("\n\n<< debug break after just doing '\(language)' \n")
		//	break
	}
	print(" ")
}



func readStringsMap(_ fileURL: URL) async -> [String: String] {
	var result: [String: String] = [:]
	if FileManager.default.fileExists(atPath: fileURL.path) {
		do {
			for try await line in fileURL.lines {
				if let keyValue = readTranslationKeyValue(line) {
					result[keyValue.key] = keyValue.value
				}
			}
		} catch {
			print("Failed reading map:")
			print(error)
		}
	}
	return result
}


func readTranslationKeyValue(_ line: String) -> (key: String, value: String)? {
	let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
	
	// Create A NSRegularExpression
	let capturePattern = #"\"(.*?)\" = \"(.*?)\";"#
	let captureRegex = try! NSRegularExpression(pattern: capturePattern, options: [])
	let matches = captureRegex.matches(in: line, options: [], range: lineRange)
	
	if let match = matches.first  {
		
		var keyValue: [String] = []
		
		// For each matched range, extract the capture group
		for rangeIndex in 0..<match.numberOfRanges {
			let matchRange = match.range(at: rangeIndex)
			
			// Ignore matching the entire string
			if matchRange == lineRange { continue }
			
			// Extract the substring matching the capture group
			if let substringRange = Range(matchRange, in: line) {
				let capture = String(line[substringRange])
				keyValue.append(capture)
			}
		}
		
		//	print("keyValue: \(keyValue)")
		if (keyValue.count == 2) {
			return (keyValue[0], keyValue[1])
		}
	}
	return nil
}

func findBundlePlistPaths(_ rootURL: URL) -> [URL] {
	var result = [URL]()
	if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
		for case let url as URL in enumerator {
			if url.pathExtension == "plist" && url.path.contains(".bundle/") && !url.path.contains("Pods/") && !url.path.contains(".framework/") {
				result.append(url)
			}
		}
	}
	return result
}

func getTitlesFromPlist(_ plistURL: URL) -> [String] {
	var result:[String] = []
	do {
		let data = try Data(contentsOf: plistURL)
		let plist = try PropertyListDecoder().decode(Root.self, from: data)
		for pref in plist.PreferenceSpecifiers {
			if let title = pref.Title, !title.isEmpty {
				// print("- found title: '\(title)'")
				result.append(title)
			}
		}
	} catch {
		print(" Failed getTitlesFromPlist: ")
		print(error)
	}
	return result
}

func touchFile(_ fileURL: URL) {
	// sanity create the folders...
	let parent = fileURL.deletingLastPathComponent()
	try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
	
	// ... and file with empty data
	try? Data().write(to: fileURL, options: .atomicWrite)
}


func shell(_ command: String) async {
	// debug shell input
	//	print("[shell]  '\(command)'")
	
	let process = Process()
	let pipe = Pipe()
	
	process.standardOutput = pipe
	process.standardError = pipe
	process.arguments = ["-c", command]
	process.launchPath = "/bin/zsh"
	process.standardInput = nil
	process.launch()
	
	process.waitUntilExit()
	
	// debug shell output
	//	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	//	let output = String(data: data, encoding: .utf8)
	//	print("[shell]  '\(output)'")
}



// MARK: - Apple Plist schema
// https://developer.apple.com/library/archive/documentation/PreferenceSettings/Conceptual/SettingsApplicationSchemaReference/Articles/RootContent.html
struct Root : Decodable {
	let PreferenceSpecifiers : [PreferenceSpecifiers]
}
struct PreferenceSpecifiers : Decodable {
	let Title, Key : String?
}
