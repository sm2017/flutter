# BOT=true ../../../../../bin/cache/dart-sdk/bin/dart --checked ../../../bin/flutter_tools.dart format --verify test/002.txt

find test/*.txt | BOT=true xargs -n 1 ../../../../../bin/cache/dart-sdk/bin/dart --checked ../../../bin/flutter_tools.dart format --verify
