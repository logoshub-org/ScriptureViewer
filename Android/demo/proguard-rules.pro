# The transpiled core and Skip's libraries look classes up by name; the demo keeps them whole.
-keep class scripture.** { *; }
-keep class skip.** { *; }
-dontwarn **
