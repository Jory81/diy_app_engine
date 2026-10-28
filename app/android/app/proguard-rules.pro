# shared_preferences_android 2.5+ calls its Kotlin code from Dart over JNI (jnigen). R8 cannot
# see those calls and removed SharedPreferencesApiRegistrar.getAll & co. from release builds
# ("NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll"), so saving the device list
# failed. Keep the whole plugin package.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
