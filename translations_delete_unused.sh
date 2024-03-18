#!/bin/bash
# requires BASH not ZSH
# created by Douglas Boberg on 5/4/23. PUBLIC DOMAIN SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.

# 0. Setup stuff
#
# match the key at the start of the line in "english_key" = "translated phrase"
keyRegex="^\"(.*)\"[[:space:]]="

# 1. Find all localizable .strings files
#
localizableFiles=()
while IFS=  read -r -d $'\0'; do
  if [[ $REPLY == *"Pods/"* ]] || [[ $REPLY == *".git/"* ]] || [[ $REPLY == *".framework/"* ]] || [[ $REPLY == *".xcworkspace/"* ]]
  then
    continue
  fi
  localizableFiles+=("$REPLY")
done < <(find . -name "*.strings" -print0)

# 2. Collect the non-empty keys from all localizable files
#
rawKeys=()
for path in "${localizableFiles[@]}"
do
  while read -r line
  do
    # echo "debug line:  $line"
    if [[ $line =~ $keyRegex ]]
    then
      # echo "debug 0: ${BASH_REMATCH[0]}"
      # echo "debug 1: ${BASH_REMATCH[1]}"
      # echo "debug 2: ${BASH_REMATCH[2]}"
      key="${BASH_REMATCH[1]}"
      if [[ ! -z "$key" ]]
      then
        rawKeys+=("$key")
      fi
    fi
  done < "$path"
done

# 3. Escape and de-dupe the keys array
#
uniqueKeys=()
while IFS= read -r -d '' key
do 
  # grep uses an interpolated string so needs backslashes escaped. "\n\n" needs to be "\\n\\n"
  key=${key//\\/\\\\}
  # echo "debug -- escape backslash: $key"

  # sed uses forward slash so we need to escape them
  key=${key//\//\\/}
  # echo "debug -- escape slash: $key"


  # sed and grep try to parse regex punctuation, so we need to escape square brackets
  key=${key//\[/\\[}
  # echo "debug -- escape left bracket: " $key
  key=${key//\]/\\]}
  # echo "debug -- escape right bracket:" $key

  uniqueKeys+=("$key")
done < <(printf "%s\0" "${rawKeys[@]}" | sort -uz)


# 4. Find all source code files, .m, .swift, and most tricky .plist
#
sourcecodeFiles=()
while IFS=  read -r -d $'\0'; do
  if [[ $REPLY == *"Pods/"* ]] || [[ $REPLY == *".git/"* ]] || [[ $REPLY == *".framework/"* ]] || [[ $REPLY == *".xcworkspace/"* ]]
  then
    continue
  fi
  sourcecodeFiles+=("$REPLY")
done < <(find . -name "*.m" -print0)
while IFS=  read -r -d $'\0'; do
  if [[ $REPLY == *"Pods/"* ]] || [[ $REPLY == *".git/"* ]] || [[ $REPLY == *".framework/"* ]] || [[ $REPLY == *".xcworkspace/"* ]]
  then
    continue
  fi
  sourcecodeFiles+=("$REPLY")
done < <(find . -name "*.swift" -print0)
while IFS=  read -r -d $'\0'; do
  if [[ $REPLY == *"Pods/"* ]] || [[ $REPLY == *".git/"* ]] || [[ $REPLY == *".framework/"* ]] || [[ $REPLY == *".xcworkspace/"* ]]
  then
    continue
  fi
  sourcecodeFiles+=("$REPLY")
done < <(find . -name "*.plist" -print0)
# for path in "${sourcecodeFiles[@]}"
# do
#   echo $path
# done




# 5. Check each key exists somewhere in .swift, .m, or .plist files
#
for key in "${uniqueKeys[@]}"
do
  found=false
  while IFS= read -r -d '' path
  do 
    # normal sanity check for key in file
    if grep -qs "$key" "$path"
    then
      found=true
      break
    fi

    # if it's a plist file we check for HTML encoded characters
    if  [[ $path == *".plist" ]] && [[ $key == *"&"* ]]
    then
      htmlKey=${key/&/&amp;}
      if grep -qs "$htmlKey" "$path"
      then
        found=true
        break
      fi
    fi
  done < <(printf "%s\0" "${sourcecodeFiles[@]}" | sort -uz)

  if [[ "$found" = true ]]
  then
    echo " ✅ $key   <is used in>   $path"
  else
    echo " 🚫 Deleting:  $key"
    for editFile in "${localizableFiles[@]}"
    do
      sed -i '' "/\"${key}\"/d" $editFile
    done
  fi
done
