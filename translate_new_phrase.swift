// translate_new_phrase.swift created by Douglas Boberg on 5/10/23. PUBLIC DOMAIN SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.

// MARK: - SETUP

// base language code for your Xcode project
let base = "en"

// target language codes for translations
var languages = ["de","es","fr","it","ja","ko","pt-BR","ru","zh-Hans"]



// MARK: - NOTES

// Translates a new phrase into all languages and appends it to the passed strings file
// This is useful if you have only a few phrases to translate and you don't want to do
// the full 'translation_setup', 'translations_delete_unused', 'translate_one_strings_file' sequence

// Can be run from command line or from Xcode. If running from Xcode, edit schema to pass in command line arguments

// >  swift translate_new_phrase.swift  Localizable.strings  "6 month subscription"  DEEPL_AUTH_KEY



// MARK: - SCRIPT

import Foundation

guard CommandLine.arguments.count == 4 else {
	print(" ")
	print("🛑  Invalid arguments: \(CommandLine.arguments.dropFirst())")
	print(" -> include a Strings filename as the 1st command line argument")
	print(" -> include a quoted phrase as the 2nd command line argument")
	print(" -> include the DeepL Auth Key as the 3rd command line argument")
	print(" ")
	exit(0)
}

let filename: String = CommandLine.arguments[1]
let phrase: String = CommandLine.arguments[2]
let deeplAuthKey: String = CommandLine.arguments[3]
guard let deeplURL = URL(string: "https://api-free.deepl.com/v2/translate") else {
	print("🛑  unable to parse the DeepL API URL!")
	print(" ")
	exit(0)
}

print("=== SETUP === \n")
print(" - Using API:   \(deeplURL)")
print(" - Using Auth Key:   \(deeplAuthKey)")

print(" ")
print("Searching for '\(filename)'")
print(" ")

// read the base first to compare to the others
guard let baseURL = findFile(filename, language: base) else {
	print("🛑  no Localizable file found for base language '\(base)'!")
	print("    you should probably run the full 'translation_setup', 'translations_delete_unused', 'translate_one_strings_file'")
	print("    sequence to get the initial files setup")
	print(" ")
	exit(0)
}
print(" - Found:  \(baseURL.path)")

// check for base value, append if not in the map
let baseMap = await readStringsMap(baseURL)
print(" ")
print("Checking if '\(base)' phrase already exists...")
if let _ = baseMap[phrase] {
	print(" - key already exists in '\(base)'")
} else {
	appendToStringsFile(baseURL, key:phrase, value:phrase)
	print(" - added new phrase to '\(base)' language")
}
print(" ")



// MARK: - main processing
for language in languages {
	print("=== BEGIN \(language) === \n")

	// read each language map
	guard let foreignURL = findFile(filename, language: language) else {
		print(" -> Skipping '\(language)' foreign language file for writing. You must manually create an empty \(language).lproj/\(filename) file.")
		continue
	}
	let foreign = await readStringsMap(foreignURL)
	if let _ = foreign[phrase] {
		print(" - key phrase already exists in '\(language)'. You must manually remove it before translating it again.")
	} else {
		let translated = await deepL(phrase, toLanguage:language)
		appendToStringsFile(foreignURL, key:phrase, value:translated)
		print(" - added '\(language)' translation:   '\(translated)'")
	}
	
	print(" ")
	print("=== FINISHED processing '\(language)' translation file. === \n\n\n")

//	print("\n\n<< debug break after just doing '\(language)' \n")
//	break
}



// MARK: - DeepL JSON schema
// { "translations": [{"detected_source_language":"EN","text":"Dies ist eine weitere Beispielzeile zum Testen"}] }
struct DeepLRoot : Decodable {
	let translations : [DeepLTranslation?]
}
struct DeepLTranslation : Decodable {
	let detected_source_language, text : String?
}


// MARK: - helper functions

func deepL(_ untranslated:String, toLanguage:String) async -> String {
	guard !untranslated.isEmpty else {
		print("Skipping empty text '\(untranslated)'")
		return untranslated
	}
	print("- Will deepL '\(toLanguage)' for: '\(untranslated)'")
	
	let authKeyItem = URLQueryItem(name: "auth_key", value: deeplAuthKey)
	let xmlHandlingItem = URLQueryItem(name: "tag_handling", value: "xml")
	let sourceLangItem = URLQueryItem(name: "source_lang", value: base.uppercased())
	let targetLangItem = URLQueryItem(name: "target_lang", value: toLanguage.hasPrefix("zh") ? "ZH" : toLanguage.uppercased())
	let textItem = URLQueryItem(name: "text", value: untranslated)
	var components = URLComponents()
	components.queryItems = ([authKeyItem, xmlHandlingItem, targetLangItem, sourceLangItem, textItem]).compactMap { $0 }
	
	guard var bodyString = components.string else {
		print("  ⚠️  Skipping translation. Failed to construct http form components \(components)")
		return untranslated
	}
	
	if bodyString.hasPrefix("?") {
		bodyString.removeFirst()
	}
	// print("bodyString: \(bodyString)")
	
	var request = URLRequest(url: deeplURL)
	request.httpMethod = "POST"
	request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
	request.httpBody = bodyString.data(using: .utf8)
	
	do {
		let (data, response) = try await URLSession.shared.data(for: request)
		guard (response as? HTTPURLResponse)?.statusCode == 200 else {
			if let dataString = String(data: data, encoding: .utf8) {
				print("http raw data string:\n \(dataString)")
			}
			print(response)
			print("  ⚠️  Skipping translation. Failed to fetch DeepL API data")
			return untranslated
		}
		
		let translated = try JSONDecoder().decode(DeepLRoot.self, from: data)
		// print("debug: DeepL Translated JSON", translated)
		if let translation = translated.translations.first??.text {
			return translation
		}
	} catch {
		print(error)
		print("  ⚠️  Skipping translation. Failed DeepL network connection")
	}
	// failed so return untranslated text
	return untranslated
}




func readStringsMap(_ fileURL: URL) async -> [String: String] {
	var result: [String: String] = [:]
	do {
		for try await line in fileURL.lines {
			//				print("line: \(line)")
			if let keyValue = readTranslationKeyValue(line) {
				result[keyValue.key] = keyValue.value
			}
		}
	} catch {
		print("Failed reading map:")
		print(error)
	}
	//	print("result: \(result)")
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

func appendToStringsFile(_ url: URL, key: String, value: String) {
	// touch the file to make sure it exists
	touchFile(url)
	
	if let fileHandle = try? FileHandle(forWritingTo: url), let data = "\n\"\(key)\" = \"\(value)\";\n".data(using: String.Encoding.utf8) {
		defer {
			fileHandle.closeFile()
		}
		fileHandle.seekToEndOfFile()
		fileHandle.write(data)
		fileHandle.closeFile()
	}
}

func findFile(_ filename: String, language:String) -> URL? {
	if let enumerator = FileManager.default.enumerator(at: URL(filePath:"."), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
		for case let url as URL in enumerator {
			if url.lastPathComponent == filename && url.path.contains("\(language).lproj/") && !url.path.contains("Pods/") && !url.path.contains(".framework/") {
				return url
			}
		}
	}
	return nil
}

func touchFile(_ fileURL: URL) {
	// sanity create the folders...
	let parent = fileURL.deletingLastPathComponent()
	try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
	
	// ... and file with empty data
	try? Data().write(to: fileURL, options: .atomicWrite)
}

