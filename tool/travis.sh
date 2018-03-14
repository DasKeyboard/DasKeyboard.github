#!/bin/bash

# Fast fail the script on failures.
set -e
# Normalize Branch variable
export BRANCH=$(if [ "$TRAVIS_PULL_REQUEST" == "false" ]; then echo $TRAVIS_BRANCH; else echo $TRAVIS_PULL_REQUEST_BRANCH; fi)

# Use the version of Dart SDK from the Flutter repository instead of whatever
# version is in the PATH.
export PATH="../flutter/bin/cache/dart-sdk/bin:$PATH"

echo "Path to dart is:"
which dart

echo "Using Dart version:"
dart --version

# echo "packages get of flutter"
# ../flutter/bin/flutter packages

# Analyze the stand-alone sample code files

for D in _includes/code/*/*; do
  # flutter analyze fails on files generated by the Dart intl package tools.
  # Skip them for now. See  https://github.com/flutter/flutter/issues/12726
  if [ "${D}" == "_includes/code/internationalization/intl" ]; then
    echo "Analyze the stand-alone sample code: ignoring files in $D"
    continue
  fi

  if [ -d "${D}" ]; then
    echo "Run flutter packages get on ${D}"
    ../flutter/bin/flutter packages get ${D}

    echo "Run flutter analyze on ${D}"
    ../flutter/bin/flutter analyze ${D}/*.dart
  fi
done

echo "Extract Dart snippets from the markdown documentation."
dart tool/extract.dart

echo "Analyzing the extracted Dart libraries."

../flutter/bin/flutter analyze example/*.dart

echo "Check formatting of the extracted Dart libraries."

FMT_RESULT=`dartfmt -n example/*.dart 2>&1`
FMT_CODE=$?
if [ $FMT_CODE -ne 0 ]; then
  echo "dartfmt exits with the following exit code: ${FMT_CODE}"
  echo "${FMT_RESULT}"
  exit 1
elif [ "${FMT_RESULT}" = "" ]; then
  echo "No formatting errors!"
else
  echo "There are formatting errors in the following files:"
  echo ""
  for FILE in $FMT_RESULT; do
    echo "===== $FILE ====="
    cp "$FILE"{,.expected}
    dartfmt -w "$FILE.expected" &> /dev/null
    echo "----- expected format -----"
    cat "$FILE.expected"
    echo "----- current format -----"
    cat "$FILE"
    echo "----- diff -----"
    echo "`diff "$FILE.expected" "$FILE"`"
    echo "===== /end $FILE ====="
    rm "$FILE.expected"
    echo ""
  done
  exit 1
fi

echo "Install jekyll."
gem install bundler
bundle install

echo "Building site."
bundle exec jekyll build

echo "Validating all links."
rake checklinks

if [ "$TRAVIS_EVENT_TYPE" = "push" ] && [ "$TRAVIS_BRANCH" = "master" ]; then
  # Deploy pushes to master to Firebase hosting.
  echo "Deploying to Firebase."
  npm install --global firebase-tools@3.16.0
  firebase -P sweltering-fire-2088 --token "$FIREBASE_TOKEN" --non-interactive deploy
fi


if [ "$ENABLE_PR_BOT" = "true" ]; then

    if [ "$BRANCH" != "master" ]; then
        echo "deploying to stage environment"
        echo $FIREBASE_FILE >> ./service_account.json
        export FIREBASE_AUTH=`oauth2l fetch --json ./service_account.json firebase.database userinfo.email 2>&1`
        cd tool/
        ../../flutter/bin/cache/dart-sdk/bin/pub get
        export PROJECT_NAME=`../../flutter/bin/cache/dart-sdk/bin/dart prdeployer.dart $BRANCH $FIREBASE_AUTH 2>&1`
        cd ../
        echo "Deploying to $PROJECT_NAME"
        npm install --global firebase-tools@3.16.0
        firebase -P "$PROJECT_NAME" --token "$FIREBASE_TOKEN_DEV" --non-interactive deploy
    fi
fi
