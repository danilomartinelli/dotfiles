alias android='emulator -avd "$(emulator -list-avds | head -n 1)" -netdelay none -netspeed full'
alias android_devices="emulator -list-avds"
alias ios='open -a Simulator'
alias ios_devices='xcrun simctl list devices available'
alias rn='npx react-native'
alias rni='npx react-native run-ios'
alias rna='npx react-native run-android'
alias pods='bundle exec pod install || pod install'
