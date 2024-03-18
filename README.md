# Translating iOS projects using DeepL:

This is a collection of command line scripts using Swift and Bash.
This is not a Swift module or package; these files are stand-alone, one-off scripts.
There is no executable to run. These work on macOS Terminal. 

You don't need to git clone this project, you can simply download the files into your workspace or project folder and run them as needed.

# before you begin

## prep your files
Make sure your project is already under version control that way you can see the changes made by this script.
It is important to check the changes these scripts may make to your sourcecode.

## prep the translation script files
Edit the top of each Swift script and set the base language code for your Xcode project:
 `let base = "en"`

Also set the array of target language codes to translate:
 `let languages = ["de","fr","ja"]`

## get a DeepL API account
https://www.deepl.com/account

Available languages are listed in API docs: https://www.deepl.com/docs-api/translate-text/translate-text/

**Chinese is always changed to Simplified** because DeepL does not support Traditional and thems the breaks.

Use curl to verify your DeepL Auth Key works

> `curl -X POST 'https://api-free.deepl.com/v2/translate' -H 'Authorization: DeepL-Auth-Key `**PLACE_THE_DeepL_Auth_Key_HERE**`' -d 'text=Hello%2C%20world!' -d 'target_lang=DE'`


# 1. run translation_setup script

Pass the relative or absolute path to your project root. It will use the current folder '.' if you don't pass a path.

> `swift translation_setup.swift /User/..etc../projectfolder/`

The script:
- runs Apple `genstrings` for normal application `.m` and `.swift` source code.
- checks the `Settings.bundle` and `InAppSettings.bundle` for any *Title* keys that don't have a translation.
- dumps the missing title keys into the `Settings` or `InAppSettings` strings file.

*note that InAppSettings is a custom file when using the InAppSettingsKit Pod and is skipped if that pod is not in the project*


# 2. optionally delete obsolete keys

*this one is a shell script because that's how I wrote it*

> `./translations_delete_unused.sh`

It takes a while to run.


# 3. run the custom translator code for each uniquely named .strings file

> `swift translate_one_strings_file.swift  Localizable.strings  DEEPL_AUTH_KEY`

> `swift translate_one_strings_file.swift  Settings.strings  DEEPL_AUTH_KEY`

> `swift translate_one_strings_file.swift  InAppSettings.strings  DEEPL_AUTH_KEY`

It should find the English file by name (a unique filename under `en.lproj` that is not a Pod or framework) and then try to match to the foreign language files.
It loops through every `"key" = "value"` in the foreign file and if it is empty or the key==value, it tries to translate it against DeepL.  


# maintenance and one-offs

You can add a single phrase to your Localizables without running all of the scripts above.

> `swift translate_a_phrase.swift  Localizable.strings  "6 month subscription"  DEEPL_AUTH_KEY`



# LICENSE and COPYRIGHT
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
