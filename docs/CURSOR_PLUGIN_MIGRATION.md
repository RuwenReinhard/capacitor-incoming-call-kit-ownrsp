# Migration: USE_FULL_SCREEN_INTENT → Heads-Up Notification

## Kontext

Google Play lehnt Apps ab, die **USE_FULL_SCREEN_INTENT** verwenden, wenn der Hauptzweck der App keine Anruf-App ist (eingeschränkte Berechtigung).  

**Lösung:** Statt einer Full-Screen Activity eine **High-Priority Heads-Up Notification** mit „Annehmen“/„Ablehnen“-Action-Buttons verwenden. Diese funktioniert auf dem Lock-Screen und im Vordergrund **ohne** die eingeschränkte Berechtigung.

Dieses Dokument beschreibt alle nötigen Änderungen am nativen Android-Teil des Plugin-Forks.

---

## 1. AndroidManifest-Änderungen (im Plugin)

**Datei:** `android/src/main/AndroidManifest.xml`

- **USE_FULL_SCREEN_INTENT Permission entfernen**  
  Zeile löschen:
  ```xml
  <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
  ```

- **Bestehende Permissions beibehalten:**
  - `INTERNET`, `VIBRATE`, `WAKE_LOCK`, `ACCESS_NOTIFICATION_POLICY`, `MANAGE_OWN_CALLS`
  - `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (für `CallkitSoundPlayerService`)

- **POST_NOTIFICATIONS sicherstellen**  
  Bereits über das Plugin (`@CapacitorPlugin` mit `POST_NOTIFICATIONS`) bzw. die App angefordert; bei Bedarf im Manifest der **Host-App** prüfen.

Die **Activity** `CallkitIncomingActivity` und der **Receiver** `CallkitIncomingBroadcastReceiver` bleiben eingetragen; sie werden weiter für Accept/Decline und optional für Tipp auf die Notification (z. B. App öffnen) genutzt.

---

## 2. Kotlin: CallkitNotificationManager (Heads-Up statt Full-Screen)

**Datei:** `android/src/main/kotlin/com/hiennv/flutter_callkit_incoming/CallkitNotificationManager.kt`

Die Anzeige des Anrufs läuft weiter über **eine Notification**; es wird **kein** Full-Screen Intent mehr gesetzt.

### 2.1 In `showIncomingNotification()` anpassen

- **Full-Screen Intent entfernen**  
  Diese Zeilen **löschen**:
  ```kotlin
  notificationBuilder.setFullScreenIntent(
      getActivityPendingIntent(notificationId, data), true
  )
  ```

- **Heads-Up-Verhalten beibehalten/erzwingen:**
  - `setCategory(NotificationCompat.CATEGORY_CALL)` (bereits vorhanden)
  - `priority = NotificationCompat.PRIORITY_MAX` (bereits vorhanden)
  - `setVisibility(NotificationCompat.VISIBILITY_PUBLIC)` (bereits vorhanden)
  - `setOngoing(true)` (bereits vorhanden)

- **Klingelton und Vibration für die Notification** (damit Heads-Up auch akustisch auffällt):
  - Statt `setSound(null)` einen Klingelton setzen, z. B.:
    ```kotlin
    val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    notificationBuilder.setSound(soundUri)
    ```
  - `setVibrate(longArrayOf(0L, 1000L, 500L, 1000L))` (bereits vorhanden; beibehalten)

- **Content Intent (Tipp auf die Notification):**  
  Optional: Beim Tippen die **Haupt-App** öffnen statt die Full-Screen Activity:
  ```kotlin
  notificationBuilder.setContentIntent(getAppPendingIntent(notificationId, data))
  ```
  (Alternativ weiter `getActivityPendingIntent(...)` nutzen, wenn beim Tippen noch die Anruf-UI gezeigt werden soll; dann öffnet sich `CallkitIncomingActivity`.)

- **Action-Buttons „Annehmen“ und „Ablehnen“**  
  Bereits vorhanden (z. B. über `addAction(declineAction)` und `addAction(acceptAction)` bzw. Custom-Views mit `setOnClickPendingIntent`). **Unverändert lassen** – sie nutzen weiter:
  - **Annehmen:** `getAcceptPendingIntent(notificationId, data)` → führt zu `TransparentActivity` mit `ACTION_CALL_ACCEPT` → Broadcast → JS-Event.
  - **Ablehnen:** `getDeclinePendingIntent(notificationId, data)` → `CallkitIncomingBroadcastReceiver` mit `ACTION_CALL_DECLINE` → JS-Event.

- **Delete Intent (Timeout):**  
  `setDeleteIntent(getTimeOutPendingIntent(notificationId, data))` beibehalten.

Zusammenfassung: In `showIncomingNotification()` nur **setFullScreenIntent entfernen**, Sound ggf. von `null` auf Ringtone umstellen, Rest (Kategorie, Priorität, Actions, Content/Delete Intent) bleibt logisch gleich.

---

## 3. Notification Channel (für Heads-Up)

**Datei:** `CallkitNotificationManager.kt` – Methode `createNotificationChanel()` (bzw. `createNotificationChanel(...)` mit den bestehenden Parametern).

- **Incoming-Call-Channel** bereits mit `NotificationManager.IMPORTANCE_HIGH` – beibehalten (wichtig für Heads-Up).
- **Sound/Vibration:**  
  Für den Incoming-Channel Sound und Vibration aktiviert lassen (wie bereits mit `setSound(null)` im Channel und `enableVibration(true)`). Nach der Umstellung auf Heads-Up: Wenn die Notification selbst einen Ringtone nutzt (siehe 2.1), den Channel-Sound entsprechend setzen (z. B. `setSound(ringtoneUri, audioAttributes)`), damit auf dem Lock-Screen Klingeln/Vibration ankommen.

Konstante für die Channel-ID bleibt z. B. `NOTIFICATION_CHANNEL_ID_INCOMING`; keine strukturelle Änderung nötig, nur ggf. Sound-Uri im Channel anpassen, falls die Notification jetzt klingelt.

---

## 4. Action-Button PendingIntents (unverändert nutzbar)

Bereits korrekt umgesetzt:

- **Accept:**  
  `getAcceptPendingIntent()` → startet `TransparentActivity` mit `ACTION_CALL_ACCEPT` und `data` → diese sendet Broadcast → `CallkitIncomingBroadcastReceiver` verarbeitet `ACTION_CALL_ACCEPT` (Sound stoppen, Notification schließen, Event an JS).

- **Decline:**  
  `getDeclinePendingIntent()` → sendet Broadcast an `CallkitIncomingBroadcastReceiver` mit `ACTION_CALL_DECLINE` (Sound stoppen, Notification schließen, ggf. Backend-Call, Event an JS).

Es sind **keine Änderungen** an den PendingIntents oder am Receiver nötig; die bestehende Logik bleibt gültig.

---

## 5. Full-Screen-Permission-UI entfernen

**Datei:** `CallkitNotificationManager.kt`

- **Methode `requestFullIntentPermission(activity: Activity?)`:**  
  Kann zu einer No-Op gemacht oder entfernt werden (kein Aufruf mehr zu `Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`).

**Datei:** `FlutterCallkitIncomingPlugin.kt` (und ggf. andere Aufrufer)

- Alle Aufrufe von `requestFullIntentPermission` entfernen oder so anpassen, dass sie nicht mehr ausgeführt werden (z. B. bei `requestPermissions` oder nach Notification-Permission).

---

## 6. FCM-Payload-Anpassung (Backend / App)

Im FCM-Data-Payload (z. B. im Objekt `call` oder in `android`):

- **`isShowFullLockedScreen`** auf **`false`** setzen **oder** den Key weglassen.  
  So wird vermieden, dass irgendwo noch explizit „Full-Screen auf Lock-Screen“ erwartet wird.

- **Rest des Payloads** (id, nameCaller, handle, avatar, extra, duration, callResponseUrl, …) **bleibt identisch**.

Die Verarbeitung in `MessagingService` / `FlutterCallkitIncomingPlugin.sendRemoteMessage` bleibt unverändert; nur der Wert von `isShowFullLockedScreen` sollte nicht mehr `true` sein.

---

## 7. Was sich NICHT ändert

- **iOS (CallKit):** Unverändert; ggf. separate Anforderung, dass auf iOS der Fullscreen am Lockscreen anders behandelt wird – das ist nicht Teil dieser Android-Migration.
- **JS/TS-Seite:** `nativeCallUI.ts`, Event-Handling (z. B. `ACTION_CALL_ACCEPT`, `ACTION_CALL_DECLINE`, `ACTION_CALL_INCOMING`, …) bleiben identisch.
- **FCM Data-Only-Message-Struktur** (z. B. `data.call` mit JSON-String) bleibt gleich.
- **Accept/Decline-Events** werden weiterhin wie bisher an die App dispatched (z. B. als `ownrsp:native-call-action` o. Ä., je nach bestehender Implementierung).

---

## 8. Kurz-Checkliste für Cursor

| Schritt | Datei | Aktion |
|--------|--------|--------|
| 1 | `AndroidManifest.xml` | `USE_FULL_SCREEN_INTENT`-Permission-Zeile entfernen |
| 2 | `CallkitNotificationManager.kt` | In `showIncomingNotification()`: `setFullScreenIntent(...)` entfernen; ggf. `setSound(ringtoneUri)` setzen; `setContentIntent(getAppPendingIntent(...))` optional |
| 3 | `CallkitNotificationManager.kt` | `requestFullIntentPermission()` leeren oder entfernen; Aufrufer in `FlutterCallkitIncomingPlugin.kt` entfernen |
| 4 | Backend / FCM-Payload | `isShowFullLockedScreen: false` oder Key weglassen |
| 5 | Channel | Prüfen, dass Incoming-Channel `IMPORTANCE_HIGH` hat und Sound/Vibration passen |

Nach der Migration: App bauen, eingehenden Anruf per FCM auslösen und prüfen, dass nur die Heads-Up-Notification mit „Annehmen“/„Ablehnen“ erscheint (kein Full-Screen) und Accept/Decline weiter korrekt an die App gemeldet werden.
