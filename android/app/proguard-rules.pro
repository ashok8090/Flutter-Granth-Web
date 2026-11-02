# The PDF foreground service is started by name from the manifest and from code;
# keep it (and its Android 15 onTimeout override) exactly as written.
-keep class com.wnm.granthprabandhan.PdfService { *; }
-keep class com.wnm.granthprabandhan.MainActivity { *; }
-keep class com.wnm.granthprabandhan.PageSyncService { *; }
-keep class com.wnm.granthprabandhan.HlFileProvider { *; }

# Round-2: Google sign-in (google_sign_in 7.x → Credential Manager). Keep the Play Services
# credential provider and Google ID classes so R8 can not strip them from release builds.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
